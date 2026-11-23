// lib/features/games/bases/drag_board.dart — the DragBoard base of Games v4 (T37): tokens in a tray, slots to drop them
// in. Plain values in, callbacks out: it reads no session and no provider, so the layout harness tests it directly and
// each template decides what a drop means (Verse Builder: a word in its place; I'rab Hunter and Drag-to-Place: a token
// in a bucket).
//
//   DragToken        one piece (id, text, `quran` = drawn in the Quran role, `image` = the item's picture, drawn
//                    above the text; a piece may be a picture alone)
//   DragSlotData     one drop zone: a placeholder / label, the tokens in it, a state, a capacity, `image` = the
//                    picture of a bucket. Pictures are drawn by `DragBoard.imageBuilder` (default: AppNetworkImage).
//   DragBoard        `board` layout (T45): `boardImage` fitted whole (aspect `boardAspect`) with a drop spot at each
//                    slot's `at` (x, y in 0..1 of the picture; a spot is at least AppTouch.min, kept inside the picture;
//                    no picture = a clean dotted board); on a wide screen the tray sits beside the picture.
//                    `line` layout (slots flow like the text, in the reading direction of the text) or `buckets`
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
import 'package:flutter_education_app/utils/widget/app_network_image.dart';

import 'stage_kit.dart';

enum DragSlotState { open, correct, wrong, fixed, hint }

class DragToken {
  const DragToken({required this.id, required this.text, this.quran = false, this.used = false, this.hint = false, this.image});
  final int id;
  final String text;
  final bool quran;

  /// The picture of the piece (an item's `image` URL): drawn above the text, or alone when [text] is empty.
  final String? image;

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
    this.image,
    this.at,
  });
  final int id;

  /// The place of a spot on a `board` (x, y in 0..1 of the picture).
  final Offset? at;

  /// The picture of a bucket (drawn beside its label).
  final String? image;

  /// The placeholder of an empty line slot, or the title of a bucket.
  final String label;
  final List<DragToken> tokens;
  final DragSlotState state;
  final int capacity;

  /// The position shown in an empty line slot ("3").
  final int? number;

  bool get full => tokens.length >= capacity;
}

enum DragBoardLayout { line, buckets, board }

/// Draws the picture at [url] in a [size] square (the board clips it to rounded corners).
typedef DragImageBuilder = Widget Function(BuildContext context, String url, double size);

Widget _networkImage(BuildContext context, String url, double size) =>
    AppNetworkImage(url: url, width: size, height: size, fit: BoxFit.cover);

/// Carries [DragBoard.imageBuilder] to the pieces.
class _BoardImages extends InheritedWidget {
  const _BoardImages({required this.builder, required super.child});
  final DragImageBuilder builder;

  /// The picture of [url] as a rounded square, or null when there is none.
  static DragImageBuilder builderOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_BoardImages>()?.builder ?? _networkImage;

  static Widget? picture(BuildContext context, String? url, double size, double radius) {
    if (url == null || url.isEmpty) return null;
    final b = context.dependOnInheritedWidgetOfExactType<_BoardImages>()?.builder ?? _networkImage;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(width: size, height: size, child: b(context, url, size)),
    );
  }

  @override
  bool updateShouldNotify(_BoardImages old) => old.builder != builder;
}

/// The side of a piece's picture and of a bucket's picture.
const double _kPieceImage = AppTouch.primary + AppSpace.md, _kBucketImage = AppTouch.min;

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
    this.imageBuilder,
    this.boardImage,
    this.boardAspect = 1.5,
    this.bucketColumns,
    this.onTapSlot,
  });

  /// A tap on a slot / spot (a piece picked by a tap goes there): the no-drag way to play.
  final ValueChanged<int>? onTapSlot;

  /// The `board` layout's picture (null = a clean board) and its width / height.
  final String? boardImage;
  final double boardAspect;

  /// How a token's / bucket's picture is drawn (tests pass a painted box); null = the app's network image.
  final DragImageBuilder? imageBuilder;

  /// `buckets` layout: how many baskets per row; null = 1 on a phone, 2 from 640 px wide (T44: I'rab Hunter asks for 2 / 3).
  final int? bucketColumns;

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
    final area = _SlotArea(
      sf: sf,
      slots: slots,
      layout: layout,
      shakeSlot: shakeSlot,
      shakeNonce: shakeNonce,
      onDrop: onDrop,
      silent: silent,
      boardImage: boardImage,
      boardAspect: boardAspect,
      bucketColumns: bucketColumns,
      onTapSlot: onTapSlot,
    );
    final tr = _Tray(sf: sf, tray: tray, onTapToken: onTapToken, silent: silent);
    final Widget body = layout == DragBoardLayout.board
        ? LayoutBuilder(builder: (context, box) {
            // a wide screen: the picture and the tray side by side, not a stretched phone
            if (box.maxWidth.isFinite && box.maxWidth >= 840) {
              return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(flex: 3, child: area),
                AppSpace.gapLg,
                Expanded(flex: 2, child: tr),
              ]);
            }
            return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [area, AppSpace.gapLg, tr]);
          })
        : Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [area, AppSpace.gapLg, tr]);
    final board = _BoardImages(builder: imageBuilder ?? _networkImage, child: body);
    return textDirection == null ? board : Directionality(textDirection: textDirection!, child: board);
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
    this.picture,
  });

  /// The token's picture, resolved by the caller (the drag feedback is built outside the board's scope).
  final Widget? picture;
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
    final pic = picture ?? _BoardImages.picture(context, token.image, _kPieceImage, sf.radius - 8);
    final label = Text(token.text, textAlign: TextAlign.center, style: style, textDirection: textDirectionOf(token.text));
    Widget chip = Container(
      constraints: BoxConstraints(minHeight: AppTouch.primary, minWidth: AppTouch.min, maxWidth: maxWidth ?? double.infinity),
      padding: pic != null
          ? const EdgeInsets.all(AppSpace.xs)
          : EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: token.quran ? 0 : AppSpace.sm),
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
      child: pic == null
          ? label
          : Column(mainAxisSize: MainAxisSize.min, children: [
              pic,
              if (token.text.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpace.xxs),
                  child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: _kPieceImage + AppSpace.lg), child: label),
                ),
            ]),
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
    final pic = _BoardImages.picture(context, tk.image, _kPieceImage, sf.radius - 8);
    final chip = _Chip(sf: sf, token: tk, state: tk.hint ? StageTileState.hint : StageTileState.idle, maxWidth: widget.maxWidth, picture: pic);
    final pressed = AnimatedScale(
      scale: _down ? 0.95 : 1,
      duration: Duration(milliseconds: appMotionOff(context) ? 0 : 90),
      curve: Curves.easeOutCubic,
      child: chip,
    );
    return Semantics(
      button: true,
      label: tk.text,
      image: tk.image != null,
      child: Draggable<int>(
        data: tk.id,
        maxSimultaneousDrags: 1,
        dragAnchorStrategy: pointerDragAnchorStrategy,
        feedback: Transform.translate(
          offset: const Offset(-40, -64),
          child: Material(
            color: Colors.transparent,
            child: _Chip(sf: sf, token: tk, lifted: true, maxWidth: widget.maxWidth, picture: pic),
          ),
        ),
        childWhenDragging: Opacity(opacity: 0.25, child: _Chip(sf: sf, token: tk, maxWidth: widget.maxWidth, picture: pic)),
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
    this.boardImage,
    this.boardAspect = 1.5,
    this.bucketColumns,
    this.onTapSlot,
  });
  final ValueChanged<int>? onTapSlot;
  final String? boardImage;
  final int? bucketColumns;
  final double boardAspect;
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
            child: _Slot(sf: sf, slot: s, layout: layout, maxWidth: maxW, onDrop: onDrop, silent: silent, onTap: onTapSlot),
          );
      if (layout == DragBoardLayout.board) {
        final aspect = boardAspect <= 0 ? 1.5 : boardAspect;
        var w = box.maxWidth.isFinite ? box.maxWidth : 320.0;
        var h = w / aspect;
        if (h > _kBoardMaxH) {
          // a tall picture is fitted whole, not stretched down the page
          h = _kBoardMaxH;
          w = h * aspect;
        }
        return Center(child: _BoardPicture(
          sf: sf,
          image: boardImage,
          width: w,
          height: h,
          spots: [
            for (final s in slots) _placeSpot(w, h, s.at ?? const Offset(0.5, 0.5), slot(s)),
          ],
        ));
      }
      if (layout == DragBoardLayout.buckets) {
        final cols = bucketColumns ?? ((box.maxWidth.isFinite && box.maxWidth >= 640) ? 2 : 1);
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

const double _kBoardMaxH = AppTouch.primary * 8, _kSpotW = 112, _kSpotH = AppTouch.primary + AppSpace.xs + 44;

/// A spot centred on [at] of a [w] x [h] picture, pushed back inside it so it is never clipped or off the edge.
Widget _placeSpot(double w, double h, Offset at, Widget child) {
  final left = (at.dx * w - _kSpotW / 2).clamp(0.0, (w - _kSpotW).clamp(0.0, w));
  final top = (at.dy * h - AppTouch.primary / 2).clamp(0.0, (h - _kSpotH).clamp(0.0, h));
  return Positioned(left: left, top: top, width: _kSpotW, height: _kSpotH, child: child);
}

/// The picture of a `board` fitted whole, or a clean dotted board when it has none; the spots sit on top.
class _BoardPicture extends StatelessWidget {
  const _BoardPicture({required this.sf, required this.image, required this.width, required this.height, required this.spots});
  final StageSurface sf;
  final String? image;
  final double width, height;
  final List<Widget> spots;

  @override
  Widget build(BuildContext context) {
    final url = image;
    Widget pic;
    if (url == null || url.isEmpty) {
      pic = CustomPaint(painter: _DotsPainter(sf.ink.withValues(alpha: 0.1)), size: Size(width, height));
    } else if (_BoardImages.builderOf(context) == _networkImage) {
      pic = AppNetworkImage(url: url, width: width, height: height, fit: BoxFit.contain);
    } else {
      pic = OverflowBox(
        maxWidth: width > height ? width : height,
        maxHeight: width > height ? width : height,
        child: _BoardImages.builderOf(context)(context, url, width > height ? width : height),
      );
    }
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: sf.paper,
        borderRadius: BorderRadius.circular(sf.radius),
        boxShadow: sf.lift(blur: 22, dy: 10),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(sf.radius),
        child: Stack(children: [Positioned.fill(child: pic), ...spots]),
      ),
    );
  }
}

class _DotsPainter extends CustomPainter {
  const _DotsPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = color;
    const step = 28.0;
    for (var y = step / 2; y < size.height; y += step) {
      for (var x = step / 2; x < size.width; x += step) {
        canvas.drawCircle(Offset(x, y), 1.6, p);
      }
    }
  }

  @override
  bool shouldRepaint(_DotsPainter old) => old.color != color;
}

class _Slot extends StatefulWidget {
  const _Slot({required this.sf, required this.slot, required this.layout, required this.onDrop, required this.silent, this.maxWidth, this.onTap});
  final ValueChanged<int>? onTap;
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
        final child = switch (widget.layout) {
          DragBoardLayout.buckets => _bucket(),
          DragBoardLayout.board => _spot(),
          DragBoardLayout.line => _line(),
        };
        return AnimatedScale(
          scale: _hover && !off ? 1.07 : 1,
          duration: Duration(milliseconds: off ? 0 : 160),
          curve: Curves.easeOutBack,
          child: widget.onTap == null
              ? child
              : GestureDetector(behavior: HitTestBehavior.opaque, onTap: () => widget.onTap!(s.id), child: child),
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

  /// A drop spot of a `board`: a ring (a check when right) with the label under it, or the pieces dropped in it.
  Widget _spot() {
    final c = _stateColor;
    final filled = s.tokens.isNotEmpty;
    final good = s.state == DragSlotState.correct;
    final text = filled ? s.tokens.map((t) => t.text).where((t) => t.isNotEmpty).join(' · ') : s.label;
    final quran = filled && s.tokens.first.quran;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        width: AppTouch.primary,
        height: AppTouch.primary,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: good ? sf.tint(sf.right, 0.3) : (_hover ? sf.tint(sf.accent, 0.3) : sf.paper.withValues(alpha: 0.9)),
          border: Border.all(color: c, width: _hover || s.state != DragSlotState.open ? 3 : 2),
          boxShadow: _hover ? [BoxShadow(color: sf.accent.withValues(alpha: 0.5), blurRadius: 16)] : sf.lift(blur: 8, dy: 3),
        ),
        child: good
            ? Icon(Icons.check_rounded, color: sf.right, size: AppIconSize.lg)
            : Text(s.number != null ? '${s.number}' : '', style: appText(17, w: FontWeight.w800, c: sf.ink.withValues(alpha: 0.55))),
      ),
      if (text.isNotEmpty) ...[
        AppSpace.gapXs,
        Container(
          constraints: const BoxConstraints(maxWidth: _kSpotW),
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.xxs),
          decoration: BoxDecoration(
            color: filled ? sf.tint(good ? sf.right : sf.wrong, 0.24) : sf.paper.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(AppRadius.pill),
            border: Border.all(color: filled ? c : sf.edge.withValues(alpha: 0.5)),
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(text,
                maxLines: 1,
                textDirection: textDirectionOf(text),
                style: quran ? quranTextStyle(18, color: sf.ink) : appText(13, w: FontWeight.w700, c: sf.ink)),
          ),
        ),
      ],
    ]);
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
        Builder(builder: (context) {
          final title = Text(s.label, style: appText(15, w: FontWeight.w700, c: sf.ink));
          final pic = _BoardImages.picture(context, s.image, _kBucketImage, AppRadius.control);
          return pic == null ? title : Row(children: [pic, AppSpace.gapSm, Expanded(child: title)]);
        }),
        AppSpace.gapXs,
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
          for (final tk in s.tokens)
            _SnapIn(key: ValueKey('b-${s.id}-${tk.id}'), child: _Chip(sf: sf, token: tk, maxWidth: widget.maxWidth)),
        ]),
      ]),
    );
  }
}

