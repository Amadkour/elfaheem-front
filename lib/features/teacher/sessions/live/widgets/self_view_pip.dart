// lib/features/teacher/sessions/live/widgets/self_view_pip.dart
//
// The self-view of the live room (D-092): my own camera in a floating box or circle that I can drag anywhere
// (it snaps to the nearer edge, or into a corner), resize, hide (a small chip brings it back) and keep on the
// stage while I'm alone. Plain values only — the room hands in the video (a LiveVideoView of the local camera)
// and the rules live in lib/features/shared/live/live_self_view.dart — so test/ui/live_self_view_layout_test.dart
// and test/visual/live_self_view_golden_test.dart pump them without a Room.
//
//   SelfViewTile        the box / circle itself: video (mirrored by the caller) or the avatar, "You" + mic, the ✋,
//                       the ⋮ button while the bar is shown, a ring while I speak.
//   SelfViewLayer       the tile on the stage: drag with the finger, settle with a short spring onto the snap
//                       point, tap / long-press; or the "Show self view" chip while hidden. Fills the stage but
//                       only its own box takes touches: drawing on a board or a shared screen goes on around it.
//   SelfViewChip        the glass pill used for "Show self view" and "Show me in a box".
//   SelfViewOptions     the options sheet's content: shape, size, fill the stage while alone, hide.
//   SelfViewSizeReporter  reports a child's laid-out size (the badge column the box keeps clear of).
library;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/display/app_fonts.dart';
import 'package:flutter_education_app/design/app_switch.dart';
import 'package:flutter_education_app/features/shared/live/live_self_view.dart';

import 'live_avatar.dart';
import 'live_palette.dart';

TextStyle _txt(double size, {FontWeight w = FontWeight.w700, Color? c, double? h}) =>
    TextStyle(fontFamily: AppFonts.family, fontSize: size, fontWeight: w, color: c ?? LivePalette.textHigh, height: h);

// ─────────────────────────────────────────────────────────────────────────────
// The tile
// ─────────────────────────────────────────────────────────────────────────────

class SelfViewTile extends StatelessWidget {
  const SelfViewTile({
    super.key,
    required this.shape,
    required this.name,
    this.video,
    this.imageUrl,
    this.micOn = true,
    this.speaking = false,
    this.handUp = false,
    this.showChrome = true,
    this.label,
    this.onMenu,
  });

  final SelfViewShape shape;

  /// The avatar's name while there is no picture yet.
  final String name;

  /// The camera (already mirrored by the caller); null → the avatar.
  final Widget? video;
  final String? imageUrl;
  final bool micOn;
  final bool speaking;
  final bool handUp;

  /// The ⋮ button and the "You" label: shown with the controls bar, hidden with it (the box is then only the
  /// picture and the muted mic).
  final bool showChrome;

  /// The caption ("You"); null → "lr_self_view_you".
  final String? label;
  final VoidCallback? onMenu;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) {
        final w = c.maxWidth.isFinite ? c.maxWidth : 96.0;
        final h = c.maxHeight.isFinite ? c.maxHeight : 128.0;
        final circle = shape == SelfViewShape.circle;
        final side = w < h ? w : h;
        final radius = circle ? side / 2 : (side * 0.15).clamp(12.0, 20.0);
        final ringColor = speaking ? LivePalette.success : LivePalette.ink(circle ? 0.78 : 0.22);
        final ringWidth = speaking ? 2.5 : (circle ? 2.0 : 1.2);
        final picture = video ??
            ColoredBox(
              color: LivePalette.surface,
              child: Center(child: LiveAvatar(name: name, imageUrl: imageUrl, size: side * 0.52, ring: false, shadow: false)),
            );
        final compact = w < 112;
        return Stack(clipBehavior: Clip.none, fit: StackFit.expand, children: [
          // Shadow + ring + picture. One widget type for both shapes (only the radius changes), so switching the
          // shape never re-creates the video renderer underneath.
          DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(radius),
              boxShadow: [
                BoxShadow(color: LivePalette.shade(0.5), blurRadius: 18, offset: const Offset(0, 6)),
                if (speaking) BoxShadow(color: LivePalette.success.withValues(alpha: 0.35), blurRadius: 16),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(radius),
              child: Stack(fit: StackFit.expand, children: [
                picture,
                if (!circle)
                  // A soft fade under the caption.
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    height: (h * 0.32).clamp(28.0, 48.0),
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Colors.transparent, LivePalette.shade(0.55)],
                          ),
                        ),
                      ),
                    ),
                  ),
              ]),
            ),
          ),
          IgnorePointer(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(radius),
                border: Border.all(color: ringColor, width: ringWidth),
              ),
            ),
          ),
          if (!circle)
            PositionedDirectional(
              start: 6,
              bottom: 6,
              end: 6,
              child: Align(
                alignment: AlignmentDirectional.bottomStart,
                child: _Caption(label: label ?? 'lr_self_view_you'.tr, micOn: micOn, showLabel: showChrome && !compact),
              ),
            )
          else if (!micOn)
            // The circle's muted mic sits on the ring, bottom-end.
            PositionedDirectional(
              end: side * 0.02,
              bottom: side * 0.02,
              child: const _MicOffDot(),
            ),
          if (handUp)
            PositionedDirectional(
              top: circle ? side * 0.02 : 6,
              start: circle ? side * 0.02 : 6,
              child: const _HandDot(),
            ),
          if (showChrome && onMenu != null)
            PositionedDirectional(
              top: circle ? -4 : 0,
              end: circle ? -4 : 0,
              child: _MenuButton(onTap: onMenu!),
            ),
        ]);
      });
}

class _Caption extends StatelessWidget {
  const _Caption({required this.label, required this.micOn, required this.showLabel});

  final String label;
  final bool micOn;
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    if (!showLabel) return micOn ? const SizedBox.shrink() : const _MicOffDot();
    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(5, 3, 8, 3),
      decoration: BoxDecoration(
        color: LivePalette.scrimLight,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(micOn ? Icons.mic_rounded : Icons.mic_off_rounded, size: 13, color: micOn ? LivePalette.textHigh : LivePalette.danger),
        const SizedBox(width: 4),
        Flexible(
          child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: _txt(11, w: FontWeight.w800)),
        ),
      ]),
    );
  }
}

class _MicOffDot extends StatelessWidget {
  const _MicOffDot();

  @override
  Widget build(BuildContext context) => Semantics(
        label: 'lr_muted'.tr,
        child: Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: LivePalette.danger,
            shape: BoxShape.circle,
            border: Border.all(color: LivePalette.bg, width: 2),
            boxShadow: [BoxShadow(color: LivePalette.shade(0.4), blurRadius: 6)],
          ),
          child: const Icon(Icons.mic_off_rounded, size: 13, color: LivePalette.textHigh),
        ),
      );
}

class _HandDot extends StatelessWidget {
  const _HandDot();

  @override
  Widget build(BuildContext context) => Container(
        width: 24,
        height: 24,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Color.alphaBlend(LivePalette.warning.withValues(alpha: 0.3), LivePalette.shade(0.6)),
          shape: BoxShape.circle,
          border: Border.all(color: LivePalette.warning.withValues(alpha: 0.8)),
        ),
        child: const Text('✋', style: TextStyle(fontSize: 12, height: 1.1)),
      );
}

class _MenuButton extends StatelessWidget {
  const _MenuButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: 'lr_self_view_options'.tr,
        child: GestureDetector(
          key: const ValueKey('self_view.menu'),
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          // A 40 px target around a 28 px dot.
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
              child: const Icon(Icons.more_horiz_rounded, size: 18, color: LivePalette.textHigh),
            ),
          ),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// The chip ("Show self view", "Show me in a box")
// ─────────────────────────────────────────────────────────────────────────────

class SelfViewChip extends StatelessWidget {
  const SelfViewChip({super.key, required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(999),
            child: Container(
              constraints: const BoxConstraints(minHeight: 40),
              padding: const EdgeInsetsDirectional.fromSTEB(10, 6, 14, 6),
              decoration: BoxDecoration(
                color: LivePalette.shade(0.58),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: LivePalette.glassBorder),
                boxShadow: [BoxShadow(color: LivePalette.shade(0.35), blurRadius: 12, offset: const Offset(0, 4))],
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(color: LivePalette.accent.withValues(alpha: 0.22), shape: BoxShape.circle),
                  child: Icon(icon, size: 15, color: LivePalette.textHigh),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: _txt(12, w: FontWeight.w800)),
                ),
              ]),
            ),
          ),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// The layer: drag, snap, hide
// ─────────────────────────────────────────────────────────────────────────────

class SelfViewLayer extends StatefulWidget {
  const SelfViewLayer({
    super.key,
    required this.prefs,
    required this.keepOut,
    required this.tile,
    required this.onMoved,
    this.hidden = false,
    this.onShow,
    this.onTap,
    this.onLongPress,
  });

  final SelfViewPrefs prefs;
  final SelfViewKeepOut keepOut;

  /// The box's content (a SelfViewTile, or the stage's content while swapped).
  final Widget tile;

  /// A drop settled: the side and the height fraction to remember.
  final void Function(SelfViewSide side, double y) onMoved;

  /// "Hide self view": the chip instead of the box.
  final bool hidden;
  final VoidCallback? onShow;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  State<SelfViewLayer> createState() => _SelfViewLayerState();
}

class _SelfViewLayerState extends State<SelfViewLayer> {
  /// The box's top-left while a finger moves it (null: at rest on its snap point).
  Offset? _drag;

  /// Where the box settles after a drop, until the parent hands in the new prefs.
  ({SelfViewSide side, double y})? _settle;

  @override
  void didUpdateWidget(covariant SelfViewLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    final s = _settle;
    if (s != null && widget.prefs.side == s.side && widget.prefs.y == s.y) _settle = null;
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) {
        final stage = c.biggest;
        final side = _settle?.side ?? widget.prefs.side;
        final y = _settle?.y ?? widget.prefs.y;
        if (widget.hidden) return Stack(children: [_chip(stage, side, y)]);
        final box = selfViewBoxSize(shape: widget.prefs.shape, size: widget.prefs.size, stage: stage);
        final rest = selfViewOffset(stage: stage, box: box, keepOut: widget.keepOut, side: side, y: y);
        final at = _drag ?? rest;
        return Stack(children: [
          AnimatedPositioned(
            key: const ValueKey('self_view.box'),
            left: at.dx,
            top: at.dy,
            width: box.width,
            height: box.height,
            duration: _drag != null ? Duration.zero : const Duration(milliseconds: 280),
            curve: Curves.easeOutBack,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.onTap,
              onLongPress: widget.onLongPress,
              onPanStart: (_) => setState(() => _drag = at),
              onPanUpdate: (d) => setState(() {
                _drag = selfViewDragClamp(stage: stage, box: box, topLeft: (_drag ?? at) + d.delta);
              }),
              onPanEnd: (d) {
                final from = _drag ?? at;
                final snap = selfViewSnap(
                  stage: stage,
                  box: box,
                  keepOut: widget.keepOut,
                  topLeft: from,
                  velocity: d.velocity.pixelsPerSecond,
                );
                setState(() {
                  _drag = null;
                  _settle = snap;
                });
                widget.onMoved(snap.side, snap.y);
              },
              onPanCancel: () => setState(() => _drag = null),
              child: Semantics(container: true, label: 'lr_self_view'.tr, child: widget.tile),
            ),
          ),
        ]);
      });

  Widget _chip(Size stage, SelfViewSide side, double y) {
    const chip = Size(0, 40);
    final at = selfViewOffset(stage: stage, box: chip, keepOut: widget.keepOut, side: side, y: y);
    final edge = side == SelfViewSide.left ? widget.keepOut.base.left : widget.keepOut.base.right;
    return Positioned(
      key: const ValueKey('self_view.hidden_chip'),
      top: at.dy,
      left: side == SelfViewSide.left ? edge : null,
      right: side == SelfViewSide.right ? edge : null,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: (stage.width - 24).clamp(120.0, 320.0)),
        child: SelfViewChip(
          icon: Icons.person_pin_rounded,
          label: 'lr_self_view_show'.tr,
          onTap: widget.onShow ?? () {},
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Options
// ─────────────────────────────────────────────────────────────────────────────

class SelfViewOptions extends StatelessWidget {
  const SelfViewOptions({
    super.key,
    required this.prefs,
    required this.onChanged,
    required this.onHide,
    this.onToStage,
    this.showAloneSwitch = true,
  });

  final SelfViewPrefs prefs;
  final ValueChanged<SelfViewPrefs> onChanged;
  final VoidCallback onHide;

  /// "Show me on the stage" (swap with the stage's content); null hides the row.
  final VoidCallback? onToStage;
  final bool showAloneSwitch;

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
        shrinkWrap: true,
        children: [
          Row(children: [
            const Icon(Icons.person_pin_rounded, size: 20, color: LivePalette.textHigh),
            const SizedBox(width: 8),
            Expanded(child: Text('lr_self_view'.tr, style: _txt(16, w: FontWeight.w800))),
          ]),
          const SizedBox(height: 4),
          Text('lr_self_view_drag_hint'.tr, style: _txt(12, w: FontWeight.w500, c: LivePalette.textMid, h: 1.35)),
          const SizedBox(height: 16),
          _Section(title: 'lr_self_view_shape'.tr),
          Row(children: [
            Expanded(
              child: _Choice(
                key: const ValueKey('self_view.shape.box'),
                selected: prefs.shape == SelfViewShape.box,
                label: 'lr_self_view_box'.tr,
                preview: const _ShapePreview(circle: false),
                onTap: () => onChanged(prefs.copyWith(shape: SelfViewShape.box)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _Choice(
                key: const ValueKey('self_view.shape.circle'),
                selected: prefs.shape == SelfViewShape.circle,
                label: 'lr_self_view_circle'.tr,
                preview: const _ShapePreview(circle: true),
                onTap: () => onChanged(prefs.copyWith(shape: SelfViewShape.circle)),
              ),
            ),
          ]),
          const SizedBox(height: 8),
          Text('lr_self_view_circle_tip'.tr, style: _txt(11.5, w: FontWeight.w500, c: LivePalette.textSoft, h: 1.35)),
          const SizedBox(height: 16),
          _Section(title: 'lr_self_view_size'.tr),
          Row(children: [
            Expanded(
              child: _Choice(
                key: const ValueKey('self_view.size.small'),
                selected: prefs.size == SelfViewSize.small,
                label: 'lr_self_view_small'.tr,
                preview: const _SizePreview(scale: 0.62),
                onTap: () => onChanged(prefs.copyWith(size: SelfViewSize.small)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _Choice(
                key: const ValueKey('self_view.size.medium'),
                selected: prefs.size == SelfViewSize.medium,
                label: 'lr_self_view_medium'.tr,
                preview: const _SizePreview(scale: 1),
                onTap: () => onChanged(prefs.copyWith(size: SelfViewSize.medium)),
              ),
            ),
          ]),
          if (showAloneSwitch) ...[
            const SizedBox(height: 14),
            _Row(
              key: const ValueKey('self_view.alone_stage'),
              icon: Icons.fit_screen_rounded,
              title: 'lr_self_view_alone_stage'.tr,
              subtitle: 'lr_self_view_alone_stage_sub'.tr,
              trailing: AppSwitch(
                value: prefs.aloneOnStage,
                semanticLabel: 'lr_self_view_alone_stage'.tr,
                onChanged: (v) => onChanged(prefs.copyWith(aloneOnStage: v)),
              ),
              onTap: () => onChanged(prefs.copyWith(aloneOnStage: !prefs.aloneOnStage)),
            ),
          ],
          if (onToStage != null) ...[
            const SizedBox(height: 8),
            _Row(
              key: const ValueKey('self_view.to_stage'),
              icon: Icons.open_in_full_rounded,
              title: 'lr_self_view_to_stage'.tr,
              onTap: onToStage!,
            ),
          ],
          const SizedBox(height: 8),
          _Row(
            key: const ValueKey('self_view.hide'),
            icon: Icons.visibility_off_rounded,
            title: 'lr_self_view_hide'.tr,
            subtitle: 'lr_self_view_hide_sub'.tr,
            onTap: onHide,
          ),
        ],
      );
}

class _Section extends StatelessWidget {
  const _Section({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(title, style: _txt(12.5, w: FontWeight.w800, c: LivePalette.textMid)),
      );
}

class _Choice extends StatelessWidget {
  const _Choice({super.key, required this.selected, required this.label, required this.preview, required this.onTap});

  final bool selected;
  final String label;
  final Widget preview;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = LivePalette.accent;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.fromLTRB(10, 12, 10, 10),
            decoration: BoxDecoration(
              color: selected ? accent.withValues(alpha: 0.16) : LivePalette.glassFaint,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: selected ? accent : LivePalette.hairline, width: selected ? 1.6 : 1),
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              SizedBox(height: 46, child: Center(child: preview)),
              const SizedBox(height: 8),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                if (selected) ...[
                  Icon(Icons.check_circle_rounded, size: 15, color: accent),
                  const SizedBox(width: 5),
                ],
                Flexible(
                  child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: _txt(12.5, w: FontWeight.w800)),
                ),
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}

class _ShapePreview extends StatelessWidget {
  const _ShapePreview({required this.circle});
  final bool circle;

  @override
  Widget build(BuildContext context) => Container(
        width: circle ? 42 : 34,
        height: circle ? 42 : 44,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(circle ? 21 : 9),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [LivePalette.accent.withValues(alpha: 0.85), LivePalette.accent2.withValues(alpha: 0.85)],
          ),
          border: Border.all(color: LivePalette.ink(0.6), width: 1.4),
        ),
        child: Icon(Icons.person_rounded, size: 22, color: LivePalette.ink(0.9)),
      );
}

class _SizePreview extends StatelessWidget {
  const _SizePreview({required this.scale});
  final double scale;

  @override
  Widget build(BuildContext context) => Container(
        width: 62,
        height: 44,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: LivePalette.ink(0.06),
          border: Border.all(color: LivePalette.hairline),
        ),
        alignment: AlignmentDirectional.bottomEnd,
        padding: const EdgeInsets.all(4),
        child: Container(
          width: 22 * scale,
          height: 28 * scale,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            color: LivePalette.accent.withValues(alpha: 0.85),
          ),
        ),
      );
}

class _Row extends StatelessWidget {
  const _Row({super.key, required this.icon, required this.title, this.subtitle, this.trailing, required this.onTap});

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            constraints: const BoxConstraints(minHeight: 52),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: LivePalette.glassFaint,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: LivePalette.hairline),
            ),
            child: Row(children: [
              Icon(icon, size: 20, color: LivePalette.textMid),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(title, style: _txt(13.5, w: FontWeight.w700)),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(subtitle!, style: _txt(11.5, w: FontWeight.w500, c: LivePalette.textSoft, h: 1.3)),
                  ],
                ]),
              ),
              if (trailing != null) ...[const SizedBox(width: 8), trailing!],
            ]),
          ),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Size reporter
// ─────────────────────────────────────────────────────────────────────────────

/// Calls [onSize] after a layout that changed the child's size (never during the layout itself).
class SelfViewSizeReporter extends SingleChildRenderObjectWidget {
  const SelfViewSizeReporter({super.key, required this.onSize, super.child});

  final ValueChanged<Size> onSize;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderSizeReporter(onSize);

  @override
  void updateRenderObject(BuildContext context, covariant _RenderSizeReporter renderObject) => renderObject.onSize = onSize;
}

class _RenderSizeReporter extends RenderProxyBox {
  _RenderSizeReporter(this.onSize);

  ValueChanged<Size> onSize;
  Size? _last;

  @override
  void performLayout() {
    super.performLayout();
    final s = size;
    if (s == _last) return;
    _last = s;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (attached) onSize(s);
    });
  }
}
