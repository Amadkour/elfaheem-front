// lib/features/teacher/sessions/live/widgets/live_control_bar.dart
//
// The live classroom's control bar — presentational only (no Room / LocalParticipant), so it can be laid out
// in tests. ControlsWidget (controls.dart) builds the list of actions and hands it over.
//
//   width < 600  → mobile: a floating glass pill with the primary actions as large round labelled buttons,
//                  a "More" button that opens a bottom sheet (showAppSheet) with everything that did not fit
//                  plus the secondary actions, and the red End button last.
//   width ≥ 600  → web / desktop: a centred floating bar with grouped segments (devices | share |
//                  reactions | end), tooltips with keyboard hints, hover states and a device chevron next to
//                  the actions that carry a device menu.
//
// The row is always laid out left-to-right so the End button is the rightmost one in Arabic too; labels are
// plain Text so Arabic shaping is unaffected.
//
// A [LiveControlAction.pinned] primary (the chat) never moves into "More" on phones: the pill makes room for it and
// its buttons shrink to fit (320 px included).
//
// Recording is not on the bar (D-095): Record / Pause / Resume / Stop and the REC time live in the room's top row
// (live_top_row.dart).
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart' show appInk, showAppSheet, AppSheetHeader;
import 'package:flutter_education_app/design/app_motion_kit.dart' show AppPressScale;
import 'package:flutter_education_app/design/app_tokens.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'live_palette.dart';
import 'package:flutter_education_app/features/shared/live/live_share_widgets.dart' show LiveAttentionBadge;

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
    this.badge = 0,
    this.attention,
    this.pinned = false,
    this.compactLabel,
  });

  /// The phone pill's label under the round button when [label] is too long for it ("Request" for "Ask to
  /// share"); tooltips, the "More" sheet and screen readers keep [label]. Null = [label].
  final String? compactLabel;

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
  /// Count shown as a small bubble on the button's corner (unread chat, raised hands); 0 hides it.
  final int badge;
  /// What this action adds to the "More" button's badge while it sits in the sheet (phones): new things only —
  /// unread chat, hands raised since the queue was last opened, unseen lobby requests. Null = [badge].
  final int? attention;

  int get attentionCount => attention ?? badge;

  /// Mobile: always in the pill, never in the "More" sheet (the chat).
  final bool pinned;

  bool get enabled => onTap != null || (menu != null && menu!.isNotEmpty);
}

/// The count bubble on a button's corner.
class _CountBadge extends StatelessWidget {
  const _CountBadge(this.count);
  final int count;
  @override
  Widget build(BuildContext context) => LiveAttentionBadge(count: count);
}

/// The phone pill's "More" badge: what waits among the actions inside the sheet. Pure (layout test).
int liveMoreBadge(List<LiveControlAction> overflow) => overflow.fold(0, (s, a) => s + a.attentionCount);

class LiveControlBar extends StatelessWidget {
  const LiveControlBar({
    super.key,
    required this.primary,
    this.secondary = const [],
    required this.end,
    this.groups,
    this.onInteraction,
    this.onLobby,
    this.waitingCount = 0,
    this.lobbyAttention,
  });

  /// Admission lobby (host only): non-null adds a "Lobby" button with [waitingCount] as its badge — on phones in the
  /// pill right after the first two primaries, on wide screens as its own segment before End.
  final VoidCallback? onLobby;
  final int waitingCount;

  /// Lobby requests the host has not seen yet (what the lobby adds to the "More" badge); null = [waitingCount].
  final int? lobbyAttention;

  LiveControlAction? get _lobbyAction => onLobby == null
      ? null
      : LiveControlAction(
          key: const ValueKey('live_room.lobby'),
          icon: waitingCount > 0 ? Icons.meeting_room_rounded : Icons.meeting_room_outlined,
          label: t('غرفة الانتظار', 'Lobby'),
          compactLabel: t('الانتظار', 'Lobby'),
          active: waitingCount > 0,
          color: waitingCount > 0 ? LivePalette.warning : null,
          badge: waitingCount,
          attention: lobbyAttention,
          shortcut: 'L',
          onTap: onLobby,
        );

  /// [primary] with the lobby button slotted in (after mic / camera).
  List<LiveControlAction> get _primaryWithLobby {
    final l = _lobbyAction;
    if (l == null) return primary;
    final at = primary.length < 2 ? primary.length : 2;
    return [...primary.take(at), l, ...primary.skip(at)];
  }

  /// Mobile: shown in the pill while they fit (extra ones move into the "More" sheet).
  final List<LiveControlAction> primary;
  /// Mobile: always in the "More" sheet.
  final List<LiveControlAction> secondary;
  /// The red End button (always last).
  final LiveControlAction end;
  /// Wide: the segments. Defaults to one group of [primary] followed by one of [secondary].
  final List<List<LiveControlAction>>? groups;
  /// Called on any pointer-down inside the bar (used to restart the auto-hide timer).
  final VoidCallback? onInteraction;

  static const _textHigh = LivePalette.textHigh;
  static const _textLow = LivePalette.textSoft;
  static const _glass = LivePalette.glass;
  static const _glassBdr = LivePalette.glassBorder;

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

  // The bar floats over the stage, so it is the one thing here with a shadow: a single soft shade, no coloured glow.
  BoxDecoration _shell(double radius) => BoxDecoration(
        color: LivePalette.surfaceHi.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: _glassBdr, width: AppBorder.hairline),
        boxShadow: [BoxShadow(color: LivePalette.shade(0.4), blurRadius: AppSpace.lg, offset: const Offset(0, AppSpace.xs - 2))],
      );

  /// The phone pill's outer gutter and the pill's own side padding.
  static const double _gutter = AppSpace.sm;
  static const double _pillSide = AppSpace.xs;

  // ── Mobile ────────────────────────────────────────────────────────────────
  Widget _mobile(BuildContext context, double width) {
    final primary = _primaryWithLobby;
    final inner = width - 2 * _gutter - 2 * _pillSide;
    final columns = (inner / 56).floor().clamp(3, 7);
    final needMore = secondary.isNotEmpty || primary.length + 1 > columns;
    final maxPrimary = needMore ? (columns - 2).clamp(1, primary.length) : primary.length;
    final firstShown = primary.take(maxPrimary).toList();
    // Pinned actions that did not fit stay in the pill anyway (kept in their order); the buttons shrink to fit.
    final shown = [for (final a in primary) if (firstShown.contains(a) || a.pinned) a];
    final overflow = [...primary.where((a) => !shown.contains(a)), ...secondary];
    final slots = shown.length + (overflow.isNotEmpty ? 1 : 0) + 1;
    final fit = inner / slots - 4;
    final base = width < 360 ? 46.0 : 52.0;
    final size = fit < base ? fit.clamp(34.0, base) : base;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: _gutter, vertical: AppSpace.xs),
      child: Container(
        padding: const EdgeInsets.fromLTRB(_pillSide, AppSpace.sm, _pillSide, AppSpace.xs),
        decoration: _shell(AppRadius.hero),
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
                  // What waits inside the sheet (unread chat, new hands, lobby requests): the "More" badge.
                  badge: liveMoreBadge(overflow),
                  onTap: () => _openMoreSheet(context, overflow),
                ),
              ),
            ),
          Expanded(child: _MobileButton(action: end, size: size, danger: true)),
        ]),
      ),
    );
  }

  void _openMoreSheet(BuildContext context, List<LiveControlAction> actions) {
    showAppSheet<void>(context, (ctx) => _MoreSheet(actions: actions));
  }

  // ── Wide ──────────────────────────────────────────────────────────────────
  Widget _wide(BuildContext context) {
    final lobby = _lobbyAction;
    final segs = [
      ...(groups ?? [primary, secondary]),
      if (lobby != null) [lobby],
    ].where((g) => g.isNotEmpty).toList();
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xs, AppSpace.md, AppSpace.md),
      child: Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Container(
            padding: const EdgeInsets.all(AppSpace.xs),
            decoration: _shell(AppRadius.block),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              for (var i = 0; i < segs.length; i++) ...[
                if (i > 0) _divider(),
                for (final a in segs[i]) Padding(padding: const EdgeInsets.symmetric(horizontal: AppSpace.xxs / 2), child: _WideButton(a)),
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
        width: AppBorder.hairline,
        height: AppSpace.lg,
        margin: const EdgeInsets.symmetric(horizontal: AppSpace.xs),
        color: _glassBdr,
      );
}

// ── Colour helpers ──────────────────────────────────────────────────────────
class _Look {
  _Look(LiveControlAction a, {bool danger = false})
      : fg = danger
            ? LivePalette.textHigh
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
                ? LivePalette.glassFaint
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
                    : LiveControlBar._glassBdr;
  // State reads from the fill and the edge alone (tone first): no coloured glow under a button.
  final Color fg;
  final Color fill;
  final Color border;
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
        // press depth on the round button only: the label under it stays still
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          AppPressScale(
            enabled: tap != null,
            scale: 0.94,
            child: Stack(clipBehavior: Clip.none, children: [
              AnimatedContainer(
                duration: AppMotion.of(context).base,
                curve: AppMotion.curve,
                width: size,
                height: size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: look.fill,
                  border: Border.all(color: look.border, width: danger ? 0 : AppBorder.hairline),
                ),
                child: a.loading ? _spinner(look.fg, size * 0.4) : Icon(a.icon, color: look.fg, size: size * 0.46),
              ),
              if (a.badge > 0) PositionedDirectional(top: -AppSpace.xxs, end: -AppSpace.xxs - 2, child: _CountBadge(a.badge)),
            ]),
          ),
          const SizedBox(height: AppSpace.xxs + 2),
          Text(
            a.compactLabel ?? a.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: AppType.overline(context).copyWith(
              letterSpacing: 0,
              height: 1.2,
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

/// The wide bar's button side (a full 48 px target, [AppTouch.min]) and how
/// long a hover waits before its tooltip.
const double _side = AppTouch.min;
const Duration _tipWait = Duration(milliseconds: 500);

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
      elevation: AppSpace.md,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.cardAll,
        side: const BorderSide(color: LiveControlBar._glassBdr),
      ),
      position: RelativeRect.fromLTRB(topLeft.dx, topLeft.dy - AppSpace.xs - AppTouch.min * (menu.length + 1), overlay.size.width - topLeft.dx - box.size.width, overlay.size.height - topLeft.dy + AppSpace.xs),
      items: [
        if (a.menuTitle != null)
          PopupMenuItem<VoidCallback>(
            enabled: false,
            height: AppSpace.xl + AppSpace.xxs,
            child: Text(a.menuTitle!, style: AppType.meta(anchor).copyWith(fontWeight: FontWeight.w600, color: LiveControlBar._textLow)),
          ),
        for (final d in menu)
          PopupMenuItem<VoidCallback>(
            value: d.onTap,
            child: Row(children: [
              Icon(d.selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                  size: AppIconSize.sm, color: d.selected ? LivePalette.accent : LiveControlBar._textLow),
              const SizedBox(width: AppSpace.sm),
              Flexible(
                child: Text(d.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.row(anchor).copyWith(
                        fontWeight: d.selected ? FontWeight.w600 : FontWeight.w400, color: LiveControlBar._textHigh)),
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
    final hoverFill = Color.alphaBlend(LivePalette.ink(0.08), look.fill);
    final motion = AppMotion.of(context);
    const outer = Radius.circular(AppRadius.control);
    const inner = Radius.circular(AppSpace.xxs);

    return Semantics(
      button: true,
      enabled: tap != null,
      label: a.label,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Tooltip(
          message: tip,
          waitDuration: _tipWait,
          decoration: BoxDecoration(color: LivePalette.tooltipBg, borderRadius: AppRadius.chipAll),
          textStyle: AppType.meta(context).copyWith(color: LivePalette.textHigh, fontWeight: FontWeight.w600),
          child: MouseRegion(
            cursor: tap == null ? SystemMouseCursors.basic : SystemMouseCursors.click,
            onEnter: (_) => setState(() => _hover = true),
            onExit: (_) => setState(() => _hover = false),
            child: GestureDetector(
              key: a.key,
              onTap: tap,
              child: AppPressScale(
                enabled: tap != null,
                scale: 0.94,
                child: Stack(clipBehavior: Clip.none, children: [
                  AnimatedContainer(
                    duration: motion.fast,
                    curve: AppMotion.curve,
                    width: _side,
                    height: _side,
                    decoration: BoxDecoration(
                      color: _hover && tap != null ? hoverFill : look.fill,
                      borderRadius: BorderRadius.horizontal(left: outer, right: hasMenu ? inner : outer),
                      border: Border.all(color: look.border, width: AppBorder.hairline),
                    ),
                    child: a.loading ? _spinner(look.fg, AppIconSize.sm) : Icon(a.icon, color: look.fg, size: AppIconSize.md),
                  ),
                  if (a.badge > 0) PositionedDirectional(top: -AppSpace.xxs - 2, end: -AppSpace.xxs - 2, child: _CountBadge(a.badge)),
                ]),
              ),
            ),
          ),
        ),
        if (hasMenu)
          Padding(
            padding: const EdgeInsetsDirectional.only(start: AppSpace.xxs / 2),
            child: Tooltip(
              message: a.menuTitle ?? a.label,
              waitDuration: _tipWait,
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                onEnter: (_) => setState(() => _hoverChevron = true),
                onExit: (_) => setState(() => _hoverChevron = false),
                child: GestureDetector(
                  key: a.key == null ? null : ValueKey('${(a.key as ValueKey?)?.value ?? a.key}.devices'),
                  onTap: () => _openMenu(context),
                  child: AnimatedContainer(
                    duration: motion.fast,
                    curve: AppMotion.curve,
                    width: _side / 2,
                    height: _side,
                    decoration: BoxDecoration(
                      color: _hoverChevron ? hoverFill : look.fill,
                      borderRadius: const BorderRadius.horizontal(left: inner, right: outer),
                      border: Border.all(color: look.border, width: AppBorder.hairline),
                    ),
                    child: Icon(Icons.expand_more_rounded, size: AppIconSize.xs, color: look.fg),
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
      waitDuration: _tipWait,
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
            child: AppPressScale(
              enabled: a.onTap != null,
              child: AnimatedContainer(
                duration: AppMotion.of(context).fast,
                curve: AppMotion.curve,
                height: _side,
                padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
                decoration: BoxDecoration(
                  color: _hover ? Color.alphaBlend(LivePalette.shade(0.12), red) : red,
                  borderRadius: AppRadius.controlAll,
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.call_end_rounded, color: LivePalette.textHigh, size: AppIconSize.md),
                  const SizedBox(width: AppSpace.xs),
                  Text(a.label, maxLines: 1, style: AppType.label(context).copyWith(color: LivePalette.textHigh, fontWeight: FontWeight.w600)),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── "More" sheet (mobile) ───────────────────────────────────────────────────
class _MoreSheet extends StatelessWidget {
  const _MoreSheet({required this.actions});
  final List<LiveControlAction> actions;

  @override
  Widget build(BuildContext context) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      AppSheetHeader('lr_more_controls'.tr),
      Flexible(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(AppSpace.sm, 0, AppSpace.sm, AppSpace.md),
          children: [
            for (final a in actions) ...[
              if (a.onTap != null || a.loading || a.menu == null) _SheetRow(a),
              if (a.menu != null && a.menu!.isNotEmpty) ...[
                // a device group: an editorial section title, more air above than below
                Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.sm, AppSpace.md, AppSpace.sm, AppSpace.xxs),
                  child: Text(a.menuTitle ?? a.label, style: AppType.section(context), maxLines: 1, overflow: TextOverflow.ellipsis),
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
    // text-safe ink for the state colour (an icon on the paper sheet), its faint tint behind the icon
    final tone = a.off ? c.danger : a.active ? (a.color ?? c.primary) : c.textMedium;
    final tint = a.off || a.active ? appInk(context, tone) : c.textMedium;
    final tile = dense ? AppSpace.xl : AppSpace.xl + AppSpace.xs;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.xxs / 2),
      // paper rows: only the switched-on action carries a tone (the primary's tint), the rest stay quiet
      child: Material(
        color: a.active && !dense ? c.primaryTint : Colors.transparent,
        borderRadius: AppRadius.controlAll,
        child: InkWell(
          key: a.key == null ? null : ValueKey('${(a.key as ValueKey?)?.value ?? a.key}.sheet'),
          borderRadius: AppRadius.controlAll,
          onTap: enabled
              ? () {
                  Navigator.of(context).pop();
                  a.onTap!();
                }
              : null,
          child: Opacity(
            opacity: enabled || a.loading ? 1 : 0.45,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: AppTouch.min),
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: dense ? AppSpace.xxs : AppSpace.xs),
                child: Row(children: [
                  Container(
                    width: tile,
                    height: tile,
                    decoration: BoxDecoration(
                      color: dense ? null : tone.withValues(alpha: 0.12),
                      borderRadius: AppRadius.controlAll,
                    ),
                    child: a.loading
                        ? _spinner(tint, AppIconSize.xs)
                        : Icon(a.icon, color: enabled ? tint : c.textLight, size: dense ? AppIconSize.sm : AppIconSize.md),
                  ),
                  const SizedBox(width: AppSpace.sm),
                  Expanded(
                    child: Text(a.label,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: a.active ? AppType.bodyStrong(context) : AppType.row(context)),
                  ),
                  if (a.badge > 0) ...[
                    const SizedBox(width: AppSpace.xs),
                    _CountBadge(a.badge),
                  ],
                  if (a.shortcut != null && !dense) ...[
                    const SizedBox(width: AppSpace.xs),
                    // a keycap: the hairline and the meta role, so it reads as a hint and not a button
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs, vertical: AppSpace.xxs / 2),
                      decoration: BoxDecoration(
                        border: Border.all(color: c.divider, width: AppBorder.hairline),
                        borderRadius: BorderRadius.circular(AppSpace.xs - 2),
                      ),
                      child: Text(a.shortcut!, style: AppType.meta(context).copyWith(fontWeight: FontWeight.w600)),
                    ),
                  ],
                  if (a.active && !dense) ...[
                    const SizedBox(width: AppSpace.xs),
                    Icon(Icons.check_circle_rounded, size: AppIconSize.sm, color: tint),
                  ],
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
