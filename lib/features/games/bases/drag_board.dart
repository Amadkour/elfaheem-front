// lib/features/games/bases/drag_board.dart — the DragBoard base of Games v4 (T37): tokens in a tray, slots to drop them
// in. Plain values in, callbacks out: it reads no session and no provider, so the layout harness tests it directly and
// each template decides what a drop means (Verse Builder: a word in its place; I'rab Hunter and Drag-to-Place: a token
// in a bucket).
//
//   DragToken        one piece (id, text, `quran` = drawn in the Quran role)
//   DragSlotData     one drop zone: a placeholder / label, the tokens in it, a state, a capacity
//   DragBoard        `line` layout (slots flow like the text, in the reading direction of the text) or `buckets`
//                    (cards with a label and a wrap of tokens). Drag: the piece lifts (scale, tilt, a deep shadow, a
//                    light haptic), the hovered slot glows and swells, a drop snaps in with a spring. A tap on a tray
//                    piece calls `onTapToken` (the template places it in the next open slot): the same board works
//                    with a mouse, a keyboard, a screen reader and a finger that does not drag.
//
// Wrong drop: the template sets the slot `wrong` and bumps `shakeSlot`; the board shakes the slot (calm round: a soft
// amber, no shake). Right: `correct` slot, the token pops in.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_motion_kit.dart' show appMotionOff;
import 'package:flutter_education_app/features/games/core/age_theme.dart';

import 'stage_kit.dart';

enum DragSlotState { open, correct, wrong, fixed, hint }

class DragToken {
  const DragToken({required this.id, required this.text, this.quran = false, this.used = false, this.hint = false});
  final int id;
  final String text;
  final bool quran;

  /// Placed: the tray keeps a faint outline so the layout does not jump.
  final bool used;

  /// The token the hint points at.
  final bool hint;
}

class DragSlotData {
  const DragSlotData({
    required this.id,
    this.label = '',
    this.tokens = const [],
    this.state = DragSlotState.open,
    this.capacity = 1,
    this.number,
  });
  final int id;

  /// The placeholder of an empty line slot, or the title of a bucket.
  final String label;
  final List<DragToken> tokens;
  final DragSlotState state;
  final int capacity;

  /// The position shown in an empty line slot ("3").
  final int? number;

  bool get full => tokens.length >= capacity;
}

enum DragBoardLayout { line, buckets }

class DragBoard extends StatelessWidget {
  const DragBoard({
    super.key,
    required this.theme,
    required this.slots,
    required this.tray,
    required this.onDrop,
    this.onTapToken,
    this.layout = DragBoardLayout.line,
    this.shakeSlot = -1,
    this.shakeNonce = 0,
    this.textDirection,
    this.silent = false,
  });

  final AgeTheme theme;
  final List<DragSlotData> slots;
  final List<DragToken> tray;
  final void Function(int tokenId, int slotId) onDrop;
  final ValueChanged<int>? onTapToken;
  final DragBoardLayout layout;

  /// The slot that shakes (a wrong drop) and a counter that re-triggers it.
  final int shakeSlot, shakeNonce;

  /// The direction the slots and the tray are laid out in (Arabic text: rtl); null = the ambient one.
  final TextDirection? textDirection;
  final bool silent;

  @override
  Widget build(BuildContext context) {
    final sf = StageSurface(theme, context);
    final body = Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _SlotArea(
        sf: sf,
        slots: slots,
        layout: layout,
        shakeSlot: shakeSlot,
        shakeNonce: shakeNonce,
        onDrop: onDrop,
        silent: silent,
      ),
      AppSpace.gapLg,
      _Tray(sf: sf, tray: tray, onTapToken: onTapToken, silent: silent),
    ]);
    return textDirection == null ? body : Directionality(textDirection: textDirection!, child: body);
  }
}

// ── the chip a token is drawn as ──────────────────────────────────────────────

class _Chip extends StatelessWidget {
  const _Chip({
    required this.sf,
    required this.token,
    this.state = StageTileState.idle,
    this.lifted = false,
    this.flat = false,
    this.maxWidth,
  });
  final StageSurface sf;
  final DragToken token;
  final StageTileState state;
  final bool lifted;

  /// A given word of a "complete" line: no edge, no lift, it is not a piece to move.
  final bool flat;
  final double? maxWidth;

  @override
  Widget build(BuildContext context) {
    final (Color fill, Color edge) = flat ? (sf.tint(sf.ink, 0.07), sf.edge) : switch (state) {
      StageTileState.correct => (sf.tint(sf.right, 0.24), sf.right),
      StageTileState.wrong => (sf.tint(sf.wrong, 0.26), sf.wrong),
      StageTileState.hint => (sf.tint(sf.gold, 0.34), sf.gold),
      _ => (sf.paper, sf.edge),
    };
    final style = token.quran
        ? quranTextStyle(20, color: sf.ink)
        : appText(17, w: FontWeight.w600, c: sf.ink);
    final e = sf.edgeWidth;
    Widget chip = Container(
      constraints: BoxConstraints(minHeight: AppTouch.primary, minWidth: AppTouch.min, maxWidth: maxWidth ?? double.infinity),
      padding: EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: token.quran ? 0 : AppSpace.sm),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(sf.radius - 4),
        border: Border.all(color: state == StageTileState.hint ? sf.gold : edge.withValues(alpha: 0.6), width: state == StageTileState.hint ? 2 : 1),
        boxShadow: flat
            ? null
            : lifted
            ? [BoxShadow(color: sf.ink.withValues(alpha: 0.3), blurRadius: 24, offset: const Offset(0, 14))]
            : [BoxShadow(color: edge, offset: Offset(0, e))],
      ),
      child: Text(token.text, textAlign: TextAlign.center, style: style, textDirection: textDirectionOf(token.text)),
    );
    if (lifted) {
      chip = Transform.rotate(angle: -0.04, child: Transform.scale(scale: 1.1, child: chip));
    }
    return chip;
  }
}

/// Pops a child in with a spring the first time it is built.
class _SnapIn extends StatelessWidget {
  const _SnapIn({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (appMotionOff(context)) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.6, end: 1),
      duration: const Duration(milliseconds: 460),
      curve: Curves.elasticOut,
      builder: (_, v, c) => Transform.scale(scale: v, child: c),
      child: child,
    );
  }
}

// ── the tray ──────────────────────────────────────────────────────────────────

class _Tray extends StatelessWidget {
  const _Tray({required this.sf, required this.tray, required this.onTapToken, required this.silent});
  final StageSurface sf;
  final List<DragToken> tray;
  final ValueChanged<int>? onTapToken;
  final bool silent;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final maxW = box.maxWidth.isFinite ? box.maxWidth : null;
      return Container(
        padding: const EdgeInsets.all(AppSpace.md),
        decoration: BoxDecoration(
          color: sf.tint(sf.ink, 0.06),
          borderRadius: BorderRadius.circular(sf.radius),
        ),
        child: Wrap(
          alignment: WrapAlignment.center,
          spacing: AppSpace.sm,
          runSpacing: AppSpace.md,
          children: [
            for (final tk in tray)
              KeyedSubtree(
                key: ValueKey('tray-${tk.id}'),
                child: tk.used
                    ? Opacity(opacity: 0.0, child: _Chip(sf: sf, token: tk, maxWidth: maxW))
                    : _TrayToken(sf: sf, token: tk, maxWidth: maxW, onTap: onTapToken, silent: silent),
              ),
          ],
        ),
      );
    });
  }
}

class _TrayToken extends StatefulWidget {
  const _TrayToken({required this.sf, required this.token, required this.onTap, required this.silent, this.maxWidth});
  final StageSurface sf;
  final DragToken token;
  final ValueChanged<int>? onTap;
  final bool silent;
  final double? maxWidth;

  @override
  State<_TrayToken> createState() => _TrayTokenState();
}

class _TrayTokenState extends State<_TrayToken> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final sf = widget.sf;
    final tk = widget.token;
    final chip = _Chip(sf: sf, token: tk, state: tk.hint ? StageTileState.hint : StageTileState.idle, maxWidth: widget.maxWidth);
    final pressed = AnimatedScale(
      scale: _down ? 0.95 : 1,
      duration: Duration(milliseconds: appMotionOff(context) ? 0 : 90),
      curve: Curves.easeOutCubic,
      child: chip,
    );
    return Semantics(
      button: true,
      label: tk.text,
      child: Draggable<int>(
        data: tk.id,
        maxSimultaneousDrags: 1,
        dragAnchorStrategy: pointerDragAnchorStrategy,
        feedback: Transform.translate(
          offset: const Offset(-40, -64),
          child: Material(
            color: Colors.transparent,
            child: _Chip(sf: sf, token: tk, lifted: true, maxWidth: widget.maxWidth),
          ),
        ),
        childWhenDragging: Opacity(opacity: 0.25, child: _Chip(sf: sf, token: tk, maxWidth: widget.maxWidth)),
        onDragStarted: () {
          HapticFeedback.lightImpact();
          stageTick(sacred: sf.calm, silent: widget.silent);
        },
        child: Listener(
          onPointerDown: (_) => setState(() => _down = true),
          onPointerUp: (_) => setState(() => _down = false),
          onPointerCancel: (_) => setState(() => _down = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onTap == null ? null : () => widget.onTap!(tk.id),
            child: pressed,
          ),
        ),
      ),
    );
  }
}

// ── the slots ─────────────────────────────────────────────────────────────────

class _SlotArea extends StatelessWidget {
  const _SlotArea({
    required this.sf,
    required this.slots,
    required this.layout,
    required this.shakeSlot,
    required this.shakeNonce,
    required this.onDrop,
    required this.silent,
  });
  final StageSurface sf;
  final List<DragSlotData> slots;
  final DragBoardLayout layout;
  final int shakeSlot, shakeNonce;
  final void Function(int, int) onDrop;
  final bool silent;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final maxW = box.maxWidth.isFinite ? box.maxWidth : null;
      Widget slot(DragSlotData s) => StageReact(
            key: ValueKey('slot-${s.id}'),
            shake: s.id == shakeSlot && !sf.calm ? shakeNonce : 0,
            child: _Slot(sf: sf, slot: s, layout: layout, maxWidth: maxW, onDrop: onDrop, silent: silent),
          );
      if (layout == DragBoardLayout.buckets) {
        final cols = (box.maxWidth.isFinite && box.maxWidth >= 640) ? 2 : 1;
        return Wrap(
          spacing: AppSpace.md,
          runSpacing: AppSpace.md,
          children: [
            for (final s in slots)
              SizedBox(
                width: box.maxWidth.isFinite ? (box.maxWidth - (cols - 1) * AppSpace.md) / cols : null,
                child: slot(s),
              ),
          ],
        );
      }
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.sm),
        decoration: BoxDecoration(
          color: sf.paper.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(sf.radius),
          boxShadow: sf.lift(blur: 22, dy: 10),
        ),
        child: Wrap(
          alignment: WrapAlignment.center,
          spacing: AppSpace.sm,
          runSpacing: AppSpace.xs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [for (final s in slots) slot(s)],
        ),
      );
    });
  }
}

class _Slot extends StatefulWidget {
  const _Slot({required this.sf, required this.slot, required this.layout, required this.onDrop, required this.silent, this.maxWidth});
  final StageSurface sf;
  final DragSlotData slot;
  final DragBoardLayout layout;
  final double? maxWidth;
  final void Function(int, int) onDrop;
  final bool silent;

  @override
  State<_Slot> createState() => _SlotState();
}

class _SlotState extends State<_Slot> {
  bool _hover = false;

  DragSlotData get s => widget.slot;
  StageSurface get sf => widget.sf;

  bool _accepts(DragTargetDetails<int> d) => s.state != DragSlotState.fixed && s.state != DragSlotState.correct && !s.full;

  @override
  Widget build(BuildContext context) {
    if (s.state == DragSlotState.fixed) {
      // a given token of a "complete the ayah" line: plain, not a target
      return _Chip(sf: sf, token: s.tokens.first, flat: true, maxWidth: widget.maxWidth);
    }
    final off = appMotionOff(context);
    return DragTarget<int>(
      onWillAcceptWithDetails: _accepts,
      onMove: (_) {
        if (!_hover) {
          setState(() => _hover = true);
          HapticFeedback.selectionClick();
        }
      },
      onLeave: (_) => setState(() => _hover = false),
      onAcceptWithDetails: (d) {
        setState(() => _hover = false);
        HapticFeedback.mediumImpact();
        stageTick(sacred: sf.calm, silent: widget.silent);
        widget.onDrop(d.data, s.id);
      },
      builder: (context, cand, rej) {
        final child = widget.layout == DragBoardLayout.buckets ? _bucket() : _line();
        return AnimatedScale(
          scale: _hover && !off ? 1.07 : 1,
          duration: Duration(milliseconds: off ? 0 : 160),
          curve: Curves.easeOutBack,
          child: child,
        );
      },
    );
  }

  Color get _stateColor => switch (s.state) {
        DragSlotState.correct => sf.right,
        DragSlotState.wrong => sf.wrong,
        DragSlotState.hint => sf.gold,
        _ => _hover ? sf.accent : sf.edge,
      };

  Widget _line() {
    final c = _stateColor;
    if (s.tokens.isNotEmpty) {
      final tk = s.tokens.first;
      final st = switch (s.state) {
        DragSlotState.correct => StageTileState.correct,
        DragSlotState.wrong => StageTileState.wrong,
        _ => StageTileState.idle,
      };
      return _SnapIn(
        key: ValueKey('in-${s.id}-${tk.id}-${s.state.name}'),
        child: _Chip(sf: sf, token: tk, state: st, maxWidth: widget.maxWidth),
      );
    }
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      width: 72,
      height: AppTouch.primary,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: _hover ? sf.tint(sf.accent, 0.14) : sf.tint(sf.ink, 0.05),
        borderRadius: BorderRadius.circular(sf.radius - 4),
        border: Border.all(color: c.withValues(alpha: _hover || s.state == DragSlotState.hint ? 1 : 0.55), width: _hover ? 2.5 : 1.5),
        boxShadow: _hover ? [BoxShadow(color: sf.accent.withValues(alpha: 0.45), blurRadius: 16)] : null,
      ),
      child: Text(s.number != null ? '${s.number}' : s.label,
          style: appText(15, w: FontWeight.w600, c: sf.ink.withValues(alpha: 0.4))),
    );
  }

  Widget _bucket() {
    final c = _stateColor;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      constraints: const BoxConstraints(minHeight: 96),
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        color: _hover ? sf.tint(sf.accent, 0.14) : sf.paper,
        borderRadius: BorderRadius.circular(sf.radius),
        border: Border.all(color: c, width: _hover || s.state != DragSlotState.open ? 2.5 : 1.5),
        boxShadow: _hover ? [BoxShadow(color: sf.accent.withValues(alpha: 0.4), blurRadius: 18)] : sf.lift(blur: 12, dy: 4),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(s.label, style: appText(15, w: FontWeight.w700, c: sf.ink)),
        AppSpace.gapXs,
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
          for (final tk in s.tokens)
            _SnapIn(key: ValueKey('b-${s.id}-${tk.id}'), child: _Chip(sf: sf, token: tk, maxWidth: widget.maxWidth)),
        ]),
      ]),
    );
  }
}

