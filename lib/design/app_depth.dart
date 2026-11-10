// lib/design/app_depth.dart
//
// Depth and motion pieces on top of the motion kit (app_motion_kit.dart), D-620 / D-621. Same rules as the kit:
// each one is driven from its current on-screen value (a second toggle mid-way turns it around, it never jumps),
// the moving part sits in a RepaintBoundary, the transform is the identity at rest, and Reduce motion (the person's,
// the system's or the Super Admin's `app.animations` switch, all in MediaQuery.disableAnimations) parks it.
//
//   AppFlip3D(front:, back:, flipped:)        a card that turns over on a perspective Y axis (a quiz answer, a
//                                             flashcard); a critically damped spring that keeps its speed when it is
//                                             turned back mid-way; toward the reading end in Arabic too; a screen
//                                             reader hears the visible face only; Reduce motion = a crossfade
//   AppParallaxImage(image:)                  a cover picture that drifts up to 8 px against its Scrollable while
//                                             the list scrolls (paint only: a Flow delegate on the scroll position);
//                                             just the picture outside a Scrollable or under Reduce motion
//   AppExpandCard(header:, child:)            a lesson / accordion card: the height opens, the chevron turns and the
//                                             body fades in, 260 ms out-curve (220 ms back); a 48 px header that is a
//                                             button with an expanded state for keyboards and screen readers
//   AppSlideIn(visible:, child:)              a feedback panel that slides in from the bottom (or the reading end)
//                                             fast and leaves faster; Reduce motion = a fade
//
// The 3D tilt for lists (AppTilt.subtle) and the rolling figure (AppOdometer / AppCountUp(roll: true)) live in the
// motion kit beside AppTilt and AppCountUp.
library;

import 'dart:math' as math;

import 'package:flutter/physics.dart';
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';

import 'app_motion_kit.dart';
import 'app_tokens.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  Flip
// ─────────────────────────────────────────────────────────────────────────────

/// A card with two faces that turns over on a perspective Y axis when [flipped] changes (D-621): a quiz answer
/// revealed, a flashcard. Both faces are laid out (the card takes the larger), only the visible one is painted, can
/// be tapped and is in the semantics tree. The turn is a critically damped spring from the current angle and speed,
/// so a second toggle mid-flip turns it back without a jump. In Arabic it turns the other way (toward the reading
/// end). Reduce motion: the faces crossfade, nothing turns.
class AppFlip3D extends StatefulWidget {
  const AppFlip3D({super.key, required this.front, required this.back, required this.flipped});

  final Widget front;
  final Widget back;

  /// True = the back face shows.
  final bool flipped;

  @override
  State<AppFlip3D> createState() => _AppFlip3DState();
}

class _AppFlip3DState extends State<AppFlip3D> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, value: widget.flipped ? 1 : 0);

  /// About 300 ms to the eye, no overshoot.
  static final SpringDescription _spring = SpringDescription.withDampingRatio(mass: 1, stiffness: 300, ratio: 1);

  @override
  void didUpdateWidget(AppFlip3D old) {
    super.didUpdateWidget(old);
    if (old.flipped == widget.flipped) return;
    final target = widget.flipped ? 1.0 : 0.0;
    if (appMotionOff(context)) {
      _c.animateTo(target, duration: const Duration(milliseconds: 160), curve: Curves.linear);
    } else {
      _c.animateWith(SpringSimulation(_spring, _c.value, target, _c.velocity, snapToEnd: true));
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  static Matrix4 _turn(double angle) {
    if (angle == 0) return Matrix4.identity();
    return Matrix4.identity()
      ..setEntry(3, 2, 0.0012)
      ..rotateY(angle);
  }

  @override
  Widget build(BuildContext context) {
    final sign = Directionality.of(context) == TextDirection.rtl ? -1.0 : 1.0;
    final reduce = appMotionOff(context);
    final front = RepaintBoundary(child: widget.front);
    final back = RepaintBoundary(child: widget.back);
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final v = _c.value;
          final showBack = v >= 0.5;
          final double frontOpacity, backOpacity;
          Matrix4 frontM = Matrix4.identity(), backM = Matrix4.identity();
          if (reduce) {
            frontOpacity = 1 - v;
            backOpacity = v;
          } else {
            frontOpacity = showBack ? 0 : 1;
            backOpacity = showBack ? 1 : 0;
            if (v > 0 && v < 1) {
              frontM = _turn(sign * v * math.pi);
              backM = _turn(sign * (v - 1) * math.pi);
            }
          }
          Widget face(Widget child, bool on, double opacity, Matrix4 m) => IgnorePointer(
                ignoring: !on,
                child: ExcludeSemantics(
                  excluding: !on,
                  child: TickerMode(
                    enabled: on || opacity > 0,
                    child: Opacity(
                      opacity: opacity.clamp(0.0, 1.0),
                      child: Transform(transform: m, alignment: Alignment.center, child: child),
                    ),
                  ),
                ),
              );
          return Stack(alignment: Alignment.center, children: [
            face(front, !showBack, frontOpacity, frontM),
            face(back, showBack, backOpacity, backM),
          ]);
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Parallax
// ─────────────────────────────────────────────────────────────────────────────

/// A cover picture that drifts against its Scrollable as it scrolls (D-621): up to [maxShift] px (8 by default),
/// so the picture seems to sit a little deeper than the card. Give it a bounded box (an AspectRatio, a SizedBox) and
/// an [image] that fills it (`BoxFit.cover`): the picture is drawn [maxShift] px larger on each side along the scroll
/// axis and clipped, so its edge never shows. It follows the nearest Scrollable along [axis] (the page, also for a
/// card inside a horizontal carousel). Nothing is built or laid out per frame: a Flow delegate repaints on the scroll
/// position. Outside a Scrollable, in an unbounded box or under Reduce motion it is just [image].
class AppParallaxImage extends StatelessWidget {
  const AppParallaxImage({super.key, required this.image, this.maxShift = 8, this.axis = Axis.vertical});

  final Widget image;
  final double maxShift;
  final Axis axis;

  /// Where the picture is drawn along the axis for an item whose centre is at [fraction] of the viewport (-1 = its
  /// leading edge, 0 = the middle, 1 = its trailing edge): -2 x [maxShift] .. 0, so the picture always covers the box.
  static double offsetFor(double fraction, double maxShift) => -maxShift * (1 + fraction.clamp(-1.0, 1.0));

  @override
  Widget build(BuildContext context) {
    final scrollable = Scrollable.maybeOf(context, axis: axis);
    if (scrollable == null || maxShift <= 0 || appMotionOff(context)) return image;
    return LayoutBuilder(builder: (context, box) {
      if (!box.hasBoundedWidth || !box.hasBoundedHeight) return image;
      return Flow(
        clipBehavior: Clip.hardEdge,
        delegate: _ParallaxDelegate(scrollable: scrollable, item: context, maxShift: maxShift),
        children: [RepaintBoundary(child: image)],
      );
    });
  }
}

class _ParallaxDelegate extends FlowDelegate {
  _ParallaxDelegate({required this.scrollable, required this.item, required this.maxShift})
      : super(repaint: scrollable.position);

  final ScrollableState scrollable;
  final BuildContext item;
  final double maxShift;

  bool get _vertical => scrollable.position.axis == Axis.vertical;

  @override
  BoxConstraints getConstraintsForChild(int i, BoxConstraints constraints) => BoxConstraints.tight(_vertical
      ? Size(constraints.maxWidth, constraints.maxHeight + 2 * maxShift)
      : Size(constraints.maxWidth + 2 * maxShift, constraints.maxHeight));

  @override
  void paintChildren(FlowPaintingContext context) {
    var fraction = 0.0;
    final viewport = scrollable.context.findRenderObject();
    final box = item.findRenderObject();
    if (viewport is RenderBox && box is RenderBox && viewport.attached && box.attached && viewport.hasSize && box.hasSize) {
      final centre = box.localToGlobal(box.size.center(Offset.zero), ancestor: viewport);
      final (at, extent, own) = _vertical
          ? (centre.dy, viewport.size.height, box.size.height)
          : (centre.dx, viewport.size.width, box.size.width);
      final half = (extent + own) / 2;
      if (half > 0) fraction = (at - extent / 2) / half;
    }
    final d = AppParallaxImage.offsetFor(fraction, maxShift);
    context.paintChild(0, transform: Matrix4.translationValues(_vertical ? 0 : d, _vertical ? d : 0, 0));
  }

  @override
  bool shouldRepaint(_ParallaxDelegate old) =>
      old.scrollable != scrollable || old.item != item || old.maxShift != maxShift;
}

// ─────────────────────────────────────────────────────────────────────────────
//  Expanding card
// ─────────────────────────────────────────────────────────────────────────────

/// A lesson / accordion card (D-621): a 48 px header row with a chevron, and a body that opens under it. The height
/// opens and the chevron turns on [AppEase.out] in 260 ms (220 ms closing) while the body fades in a beat after it,
/// always from where it is (tap twice quickly and it turns around). The header is ONE button for a screen reader with
/// its expanded / collapsed state, takes focus, opens with Enter or Space and shows the focus ring. A closed body is
/// kept (its state survives) but is offstage: not painted, not focusable, not read.
///
/// [expanded] is where it starts and, when the parent changes it, where it goes; a tap toggles it and reports
/// [onExpandedChanged]. [card] false drops the paper card (inside a list that is already a card).
class AppExpandCard extends StatefulWidget {
  const AppExpandCard({
    super.key,
    required this.header,
    required this.child,
    this.expanded = false,
    this.onExpandedChanged,
    this.card = true,
  });

  final Widget header;
  final Widget child;
  final bool expanded;
  final ValueChanged<bool>? onExpandedChanged;
  final bool card;

  @override
  State<AppExpandCard> createState() => _AppExpandCardState();
}

class _AppExpandCardState extends State<AppExpandCard> with SingleTickerProviderStateMixin {
  late bool _open = widget.expanded;
  late final AnimationController _c = AnimationController(
    vsync: this,
    value: _open ? 1 : 0,
    duration: const Duration(milliseconds: 260),
    reverseDuration: const Duration(milliseconds: 220),
  );
  bool _focused = false;

  @override
  void didUpdateWidget(AppExpandCard old) {
    super.didUpdateWidget(old);
    if (widget.expanded != old.expanded && widget.expanded != _open) _go(widget.expanded);
  }

  void _go(bool open) {
    _open = open;
    if (appMotionOff(context)) {
      _c.value = open ? 1 : 0;
    } else if (open) {
      _c.animateTo(1, curve: AppEase.out);
    } else {
      _c.animateBack(0, curve: AppEase.out);
    }
  }

  void _toggle() {
    setState(() => _go(!_open));
    widget.onExpandedChanged?.call(_open);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final radius = BorderRadius.circular(AppRadius.card);
    final ring = _focused && FocusManager.instance.highlightMode == FocusHighlightMode.traditional;
    final header = MergeSemantics(
      child: Semantics(
        button: true,
        expanded: _open,
        child: InkWell(
          onTap: _toggle,
          onFocusChange: (f) => setState(() => _focused = f),
          borderRadius: widget.card ? radius : null,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: AppTouch.min),
            child: Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.md, AppSpace.sm, AppSpace.sm, AppSpace.sm),
              child: Row(children: [
                Expanded(child: widget.header),
                const SizedBox(width: AppSpace.xs),
                RotationTransition(
                  turns: _c.drive(Tween(begin: 0.0, end: 0.5)),
                  child: ExcludeSemantics(
                    child: Icon(Icons.expand_more_rounded, size: AppIconSize.lg, color: c.textMedium),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
    final body = AnimatedBuilder(
      animation: _c,
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.md, 0, AppSpace.md, AppSpace.md),
        child: widget.child,
      ),
      builder: (context, child) {
        final v = _c.value;
        final closed = v == 0 && !_open;
        return Offstage(
          offstage: closed,
          child: TickerMode(
            enabled: !closed,
            child: ClipRect(
              child: Align(
                alignment: AlignmentDirectional.topStart,
                heightFactor: v,
                child: Opacity(opacity: ((v - 0.25) / 0.75).clamp(0.0, 1.0), child: child),
              ),
            ),
          ),
        );
      },
    );
    final column = Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      header,
      RepaintBoundary(child: body),
    ]);
    if (!widget.card) return Material(type: MaterialType.transparency, child: column);
    return Material(
      color: c.cardBg,
      surfaceTintColor: Colors.transparent,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(color: ring ? c.primary : c.divider, width: ring ? AppBorder.focus : AppBorder.hairline),
      ),
      child: column,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Slide-in panel
// ─────────────────────────────────────────────────────────────────────────────

/// Where an [AppSlideIn] comes from: the bottom, or the reading end (the right in English, the left in Arabic).
enum AppSlideFrom { bottom, end }

/// A feedback panel ("Correct", "Saved", a hint) that slides in by its own size from [from] when [visible] turns
/// true: 260 ms on [AppEase.out], and leaves the same way in 180 ms. Interruptible both ways (it turns around from
/// where it is). It fades over the first part of the way in, so it never shows a hard edge. While hidden it takes no
/// room and is not in the tree; leaving, it cannot be tapped and is not read. [liveRegion]: a screen reader announces
/// it when it appears. Put it where it may overlap (a Stack, the bottom of a page): it only moves, it does not push.
/// Reduce motion: a 150 ms fade, no movement.
class AppSlideIn extends StatefulWidget {
  const AppSlideIn({
    super.key,
    required this.visible,
    required this.child,
    this.from = AppSlideFrom.bottom,
    this.liveRegion = true,
  });

  final bool visible;
  final Widget child;
  final AppSlideFrom from;
  final bool liveRegion;

  @override
  State<AppSlideIn> createState() => _AppSlideInState();
}

class _AppSlideInState extends State<AppSlideIn> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, value: widget.visible ? 1 : 0);

  @override
  void initState() {
    super.initState();
    // gone: take it out of the tree (an exit always ends on a status change)
    _c.addStatusListener((_) {
      if (mounted && !widget.visible && _gone) setState(() {});
    });
  }

  @override
  void didUpdateWidget(AppSlideIn old) {
    super.didUpdateWidget(old);
    if (old.visible == widget.visible) return;
    final reduce = appMotionOff(context);
    if (widget.visible) {
      _c.animateTo(1, duration: Duration(milliseconds: reduce ? 150 : 260), curve: reduce ? Curves.linear : AppEase.out);
    } else {
      _c.animateBack(0, duration: Duration(milliseconds: reduce ? 150 : 180), curve: reduce ? Curves.linear : AppEase.out);
    }
  }

  bool get _gone => !_c.isAnimating && _c.value == 0;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.visible && _gone) return const SizedBox.shrink();
    final reduce = appMotionOff(context);
    final sign = Directionality.of(context) == TextDirection.rtl ? -1.0 : 1.0;
    final bottom = widget.from == AppSlideFrom.bottom;
    return IgnorePointer(
      ignoring: !widget.visible,
      child: ExcludeSemantics(
        excluding: !widget.visible,
        child: Semantics(
          container: true,
          liveRegion: widget.liveRegion,
          child: RepaintBoundary(
            child: AnimatedBuilder(
              animation: _c,
              child: RepaintBoundary(child: widget.child),
              builder: (context, child) {
                final v = _c.value;
                if (reduce) return Opacity(opacity: v, child: child);
                final rest = 1 - v;
                return Opacity(
                  opacity: (v / 0.4).clamp(0.0, 1.0),
                  child: FractionalTranslation(
                    translation: bottom ? Offset(0, rest) : Offset(sign * rest, 0),
                    child: child,
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
