// lib/features/teacher/sessions/live/widgets/presenter_cam_box.dart
//
// The presenter's camera over a share (D-094): while a screen share or the whiteboard fills the stage, every viewer
// sees the presenter's camera in a floating box — the self-view's look (SelfViewTile), another source — and up to a
// few other cameras as small bubbles next to it. Plain values only (the room hands in LiveVideoViews; the rules are
// in lib/features/shared/live/live_presenter_cam.dart), so test/ui/presenter_cam_layout_test.dart and
// test/visual/presenter_cam_golden_test.dart pump it without a Room.
//
//   PresenterCamItem    one camera: name, the video (null → the avatar), photo, mic, speaking, ✋.
//   PresenterCamLayer   fills the stage, but only the box / bubbles / pill take touches (the stage tap, drawing on a
//                       board or a share go on around them). Drag the box anywhere: it snaps to the nearer edge or a
//                       corner, never onto the self-view ([avoid]). Tap → [onTap] (the room toggles its bars), ⋮ /
//                       long-press → [onMenu], "–" → [onCollapse]; a bubble's tap pins that camera into the box.
//   PresenterCamPill    the box minimized to a name ("Ahmed · +2"); a tap brings the camera back.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/display/app_fonts.dart';
import 'package:flutter_education_app/features/shared/live/live_presenter_cam.dart';
import 'package:flutter_education_app/features/shared/live/live_self_view.dart';

import 'live_avatar.dart';
import 'live_palette.dart';
import 'self_view_pip.dart';

TextStyle _txt(double size, {FontWeight w = FontWeight.w700, Color? c, double? h}) =>
    TextStyle(fontFamily: AppFonts.family, fontSize: size, fontWeight: w, color: c ?? LivePalette.textHigh, height: h);

/// One camera the layer draws.
@immutable
class PresenterCamItem {
  const PresenterCamItem({
    required this.id,
    required this.name,
    this.video,
    this.imageUrl,
    this.micOn = true,
    this.speaking = false,
    this.handUp = false,
  });

  final String id;
  final String name;

  /// The camera (a LiveVideoView); null → the avatar.
  final Widget? video;
  final String? imageUrl;
  final bool micOn;
  final bool speaking;
  final bool handUp;
}

class PresenterCamLayer extends StatefulWidget {
  const PresenterCamLayer({
    super.key,
    required this.prefs,
    required this.keepOut,
    required this.selfSide,
    required this.onMoved,
    this.main,
    this.bubbles = const [],
    this.more = 0,
    this.avoid,
    this.collapsed = false,
    this.showChrome = true,
    this.onTap,
    this.onMenu,
    this.onCollapse,
    this.onExpand,
    this.onPin,
    this.onMore,
    this.content,
    this.rail,
  });

  final PresenterCamPrefs prefs;
  final SelfViewKeepOut keepOut;

  /// D-105: the shared picture on this stage (null: a board or unknown): the box floats over it
  /// (selfViewOverContent), so the camera is in front of the content, not in the bars beside it.
  final Rect? Function(Size stage)? content;

  /// D-109: the whiteboard's vertical scrollbar (its hit strip) on this stage: the box rests beside it, on the page's
  /// corner still, never on the thumb.
  final Rect? Function(Size stage)? rail;

  /// The side my self-view is on: an unmoved box sits on the other one.
  final SelfViewSide selfSide;

  /// A drop settled: the side and the height fraction to remember.
  final void Function(SelfViewSide side, double y) onMoved;

  /// The camera in the box (null: bubbles only).
  final PresenterCamItem? main;
  final List<PresenterCamItem> bubbles;

  /// Cameras on but not drawn: a "+n" bubble.
  final int more;

  /// My self-view's rectangle on a stage of the given size (null: none); the box never rests on it.
  final Rect? Function(Size stage)? avoid;

  /// Minimized to a name.
  final bool collapsed;

  /// The ⋮ and "–" buttons and the caption's name: shown with the room's bar.
  final bool showChrome;
  final VoidCallback? onTap;
  final VoidCallback? onMenu;
  final VoidCallback? onCollapse;
  final VoidCallback? onExpand;
  final ValueChanged<String>? onPin;
  final VoidCallback? onMore;

  @override
  State<PresenterCamLayer> createState() => _PresenterCamLayerState();
}

class _PresenterCamLayerState extends State<PresenterCamLayer> {
  Offset? _drag;
  ({SelfViewSide side, double y})? _settle;

  @override
  void didUpdateWidget(covariant PresenterCamLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    final s = _settle;
    if (s != null && widget.prefs.side == s.side && widget.prefs.y == s.y) _settle = null;
  }

  int get _bubbleCount => widget.bubbles.length + (widget.more > 0 ? 1 : 0);

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) {
        final stage = c.biggest;
        if (widget.main == null && _bubbleCount == 0) return const SizedBox.shrink();
        var box = widget.main == null
            ? Size.zero
            : selfViewBoxSize(shape: widget.prefs.shape, size: widget.prefs.size, stage: stage);
        // D-105: over a shared picture the box floats on the picture's corner (scaled to it), not in the bars.
        var keepOut = widget.keepOut;
        if (!widget.collapsed && widget.main != null) {
          final over = selfViewOverContent(stage: stage, box: box, keepOut: keepOut, content: widget.content?.call(stage));
          if (over != null) (box, keepOut) = (over.box, over.keepOut);
        }
        final d = presenterBubbleSize(stage.width);
        final unit = presenterDockSize(box: box, bubbles: _bubbleCount, bubble: d);
        keepOut = selfViewClearOfRail(
            keepOut: keepOut, stage: stage, width: widget.collapsed ? 180 : unit.width, rail: widget.rail?.call(stage));
        final avoid = widget.avoid?.call(stage);
        final spot = _settle ??
            presenterCamSpot(
              stage: stage,
              unit: widget.collapsed ? const Size(180, 44) : unit,
              keepOut: keepOut,
              side: widget.prefs.side,
              y: widget.prefs.y,
              selfSide: widget.selfSide,
              avoid: avoid,
            );
        if (widget.collapsed) return Stack(children: [_pill(stage, spot)]);
        final rest = selfViewOffset(stage: stage, box: unit, keepOut: keepOut, side: spot.side, y: spot.y);
        final at = _drag ?? rest;
        final above = presenterRowAbove(spot.y);
        final align = spot.side == SelfViewSide.left ? Alignment.centerLeft : Alignment.centerRight;
        final row = _bubbleCount == 0
            ? null
            : SizedBox(
                height: d,
                child: Align(alignment: align, child: _bubbleRow(d, spot.side)),
              );
        final boxWidget = widget.main == null
            ? null
            : Align(
                alignment: align,
                child: SizedBox.fromSize(size: box, child: _tile(widget.main!)),
              );
        final children = <Widget>[
          if (above && row != null) ...[row, if (boxWidget != null) const SizedBox(height: kPresenterRowGap)],
          ?boxWidget,
          if (!above && row != null) ...[if (boxWidget != null) const SizedBox(height: kPresenterRowGap), row],
        ];
        return Stack(children: [
          AnimatedPositioned(
            key: const ValueKey('presenter_cam.box'),
            left: at.dx,
            top: at.dy,
            width: unit.width,
            height: unit.height,
            duration: _drag != null ? Duration.zero : const Duration(milliseconds: 280),
            curve: Curves.easeOutBack,
            child: GestureDetector(
              // Only the box and the bubbles take touches: the unit's empty corners stay the stage's.
              behavior: HitTestBehavior.deferToChild,
              onPanStart: (_) => setState(() => _drag = at),
              onPanUpdate: (dd) => setState(() {
                _drag = selfViewDragClamp(stage: stage, box: unit, topLeft: (_drag ?? at) + dd.delta);
              }),
              onPanEnd: (dd) {
                final from = _drag ?? at;
                final snap = selfViewSnap(
                  stage: stage,
                  box: unit,
                  keepOut: keepOut,
                  topLeft: from,
                  velocity: dd.velocity.pixelsPerSecond,
                );
                // A drop onto the self-view moves on to the nearest free spot.
                final free = presenterCamSpot(
                  stage: stage,
                  unit: unit,
                  keepOut: keepOut,
                  side: snap.side,
                  y: snap.y,
                  selfSide: widget.selfSide,
                  avoid: avoid,
                );
                setState(() {
                  _drag = null;
                  _settle = free;
                });
                widget.onMoved(free.side, free.y);
              },
              onPanCancel: () => setState(() => _drag = null),
              child: Column(mainAxisSize: MainAxisSize.min, children: children),
            ),
          ),
        ]);
      });

  Widget _tile(PresenterCamItem m) {
    final circle = widget.prefs.shape == SelfViewShape.circle;
    final chrome = widget.showChrome;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      onLongPress: widget.onMenu,
      child: Semantics(
        container: true,
        label: '${'lr_presenter_cam'.tr}: ${m.name}',
        child: Stack(clipBehavior: Clip.none, fit: StackFit.expand, children: [
          SelfViewTile(
            shape: widget.prefs.shape,
            name: m.name,
            label: m.name,
            video: m.video,
            imageUrl: m.imageUrl,
            micOn: m.micOn,
            speaking: m.speaking,
            // With the bar, the "–" button takes the top-start corner: the ✋ moves under it.
            handUp: m.handUp && !(chrome && widget.onCollapse != null),
            showChrome: chrome,
            onMenu: widget.onMenu,
          ),
          if (chrome && widget.onCollapse != null) ...[
            PositionedDirectional(
              top: circle ? -4 : 0,
              start: circle ? -4 : 0,
              child: _RoundButton(
                key: const ValueKey('presenter_cam.collapse'),
                icon: Icons.remove_rounded,
                label: 'lr_presenter_cam_collapse'.tr,
                onTap: widget.onCollapse!,
              ),
            ),
            if (m.handUp)
              PositionedDirectional(top: circle ? 34 : 40, start: circle ? 2 : 6, child: const _HandDot()),
          ],
        ]),
      ),
    );
  }

  Widget _bubbleRow(double d, SelfViewSide side) {
    final items = <Widget>[
      for (final b in widget.bubbles)
        _Bubble(
          key: ValueKey('presenter_cam.bubble.${b.id}'),
          item: b,
          size: d,
          onTap: widget.onPin == null ? null : () => widget.onPin!(b.id),
        ),
      if (widget.more > 0) _MoreBubble(key: const ValueKey('presenter_cam.more'), count: widget.more, size: d, onTap: widget.onMore),
    ];
    return Row(
      mainAxisSize: MainAxisSize.min,
      // The row grows away from the edge it hugs, in both languages.
      textDirection: side == SelfViewSide.left ? TextDirection.ltr : TextDirection.rtl,
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const SizedBox(width: kPresenterBubbleGap),
          items[i],
        ],
      ],
    );
  }

  Widget _pill(Size stage, ({SelfViewSide side, double y}) spot) {
    const h = Size(0, 44);
    final at = selfViewOffset(stage: stage, box: h, keepOut: widget.keepOut, side: spot.side, y: spot.y);
    final edge = spot.side == SelfViewSide.left ? widget.keepOut.base.left : widget.keepOut.base.right;
    final m = widget.main ?? (widget.bubbles.isEmpty ? null : widget.bubbles.first);
    // The others beside the name on the pill.
    final extra = widget.bubbles.length + widget.more - (widget.main == null ? 1 : 0);
    return Positioned(
      key: const ValueKey('presenter_cam.pill'),
      top: at.dy,
      left: spot.side == SelfViewSide.left ? edge : null,
      right: spot.side == SelfViewSide.right ? edge : null,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: (stage.width * 0.6).clamp(120.0, 280.0)),
        child: PresenterCamPill(
          name: m?.name ?? '',
          imageUrl: m?.imageUrl,
          speaking: m?.speaking ?? false,
          extra: extra < 0 ? 0 : extra,
          onTap: widget.onExpand ?? () {},
        ),
      ),
    );
  }
}

/// The box minimized: the presenter's avatar, name and "+n" others, a camera icon; a tap brings it back.
class PresenterCamPill extends StatelessWidget {
  const PresenterCamPill({
    super.key,
    required this.name,
    required this.onTap,
    this.imageUrl,
    this.speaking = false,
    this.extra = 0,
  });

  final String name;
  final String? imageUrl;
  final bool speaking;

  /// Other cameras in the minimized dock.
  final int extra;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: '${'lr_presenter_cam_show'.tr}: $name',
        excludeSemantics: true,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(999),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              constraints: const BoxConstraints(minHeight: 44),
              padding: const EdgeInsetsDirectional.fromSTEB(5, 5, 12, 5),
              decoration: BoxDecoration(
                color: LivePalette.shade(0.62),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: speaking ? LivePalette.success : LivePalette.glassBorder,
                  width: speaking ? 1.6 : 1,
                ),
                boxShadow: [BoxShadow(color: LivePalette.shade(0.35), blurRadius: 14, offset: const Offset(0, 5))],
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                LiveAvatar(name: name, imageUrl: imageUrl, size: 32, ring: false, shadow: false),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: _txt(12.5, w: FontWeight.w800)),
                ),
                if (extra > 0) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: LivePalette.ink(0.14), borderRadius: BorderRadius.circular(999)),
                    // "+2" reads the same in Arabic (never "2+").
                    child: Text('+$extra',
                        textDirection: TextDirection.ltr, style: _txt(11, w: FontWeight.w800, c: LivePalette.textMid)),
                  ),
                ],
                const SizedBox(width: 8),
                Icon(Icons.videocam_rounded, size: 16, color: LivePalette.accent),
              ]),
            ),
          ),
        ),
      );
}

class _Bubble extends StatelessWidget {
  const _Bubble({super.key, required this.item, required this.size, this.onTap});

  final PresenterCamItem item;
  final double size;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ring = item.speaking ? LivePalette.success : LivePalette.ink(0.7);
    return Tooltip(
      message: item.name,
      child: Semantics(
        button: onTap != null,
        label: item.name,
        excludeSemantics: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: SizedBox(
            width: size,
            height: size,
            child: Stack(clipBehavior: Clip.none, fit: StackFit.expand, children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(color: LivePalette.shade(0.45), blurRadius: 12, offset: const Offset(0, 4)),
                    if (item.speaking) BoxShadow(color: LivePalette.success.withValues(alpha: 0.35), blurRadius: 12),
                  ],
                ),
                child: ClipOval(
                  child: item.video ??
                      ColoredBox(
                        color: LivePalette.surface,
                        child: Center(
                          child: LiveAvatar(name: item.name, imageUrl: item.imageUrl, size: size * 0.8, ring: false, shadow: false),
                        ),
                      ),
                ),
              ),
              IgnorePointer(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: ring, width: item.speaking ? 2.2 : 1.6),
                  ),
                ),
              ),
              if (!item.micOn)
                PositionedDirectional(
                  end: -3,
                  bottom: -3,
                  child: Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      color: LivePalette.danger,
                      shape: BoxShape.circle,
                      border: Border.all(color: LivePalette.bg, width: 1.5),
                    ),
                    child: const Icon(Icons.mic_off_rounded, size: 10, color: LivePalette.textHigh),
                  ),
                ),
              if (item.handUp)
                const PositionedDirectional(top: -5, start: -5, child: _HandDot(size: 20)),
            ]),
          ),
        ),
      ),
    );
  }
}

class _MoreBubble extends StatelessWidget {
  const _MoreBubble({super.key, required this.count, required this.size, this.onTap});

  final int count;
  final double size;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: onTap != null,
        label: 'lr_presenter_cam_more'.tr.replaceAll('{n}', '$count'),
        excludeSemantics: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Container(
            width: size,
            height: size,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: LivePalette.shade(0.6),
              shape: BoxShape.circle,
              border: Border.all(color: LivePalette.glassBorder, width: 1.4),
              boxShadow: [BoxShadow(color: LivePalette.shade(0.4), blurRadius: 12, offset: const Offset(0, 4))],
            ),
            child: Text('+$count', textDirection: TextDirection.ltr, style: _txt(size * 0.3, w: FontWeight.w800)),
          ),
        ),
      );
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({super.key, required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: label,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          // A 40 px target around a 28 px dot (the same as the self-view's ⋮).
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: LivePalette.shade(0.55),
                shape: BoxShape.circle,
                border: Border.all(color: LivePalette.glassBorder),
              ),
              child: Icon(icon, size: 18, color: LivePalette.textHigh),
            ),
          ),
        ),
      );
}

class _HandDot extends StatelessWidget {
  const _HandDot({this.size = 24});

  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Color.alphaBlend(LivePalette.warning.withValues(alpha: 0.3), LivePalette.shade(0.6)),
          shape: BoxShape.circle,
          border: Border.all(color: LivePalette.warning.withValues(alpha: 0.8)),
        ),
        child: Text('✋', style: TextStyle(fontSize: size * 0.5, height: 1.1)),
      );
}
