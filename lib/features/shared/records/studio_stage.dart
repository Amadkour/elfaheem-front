// lib/features/shared/records/studio_stage.dart — the texts and pictures over the Studio's picture (D-591): drawn at
// the playhead's moment with their animation ([studioOverlayLook]), dragged to place, the selected one resized by its
// corner. Plain values in, gestures out (test/ui/studio_timeline_test.dart pumps it).
//
//   The text is drawn by the app's own text engine in the chosen catalog font (AppFonts) — Arabic shaped and right to
//   left like everywhere in the app — and the very same painter ([studioTextPainter]) rasterises it to the PNG the
//   server lays over the video ([studioRasterText]), at the video's own size: the preview IS the render (D-591).
library;

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/display/app_fonts.dart';

import '../../admin/admin_common.dart' show t;
import 'studio_project.dart';

/// The widest a text may run before it wraps, as a share of the frame.
const studioTextMaxWidth = 0.92;

/// The text's look at a letter height of [px] (shared by the preview and the PNG).
TextStyle studioTextStyle(StudioOverlay o, double px) {
  final f = AppFonts.byIdOrDefault(AppFonts.catalog.any((x) => x.id == o.fontId) ? o.fontId : AppFonts.arabicDefault);
  return TextStyle(
    fontFamily: f.family,
    fontFamilyFallback: [AppFonts.byIdOrDefault(AppFonts.arabicDefault).family, AppFonts.byIdOrDefault(AppFonts.latinDefault).family],
    fontSize: px,
    height: 1.25,
    fontWeight: o.bold ? FontWeight.w700 : FontWeight.w500,
    color: Color(o.color),
    shadows: o.background == null ? [Shadow(color: const Color(0x99000000), blurRadius: px * 0.08, offset: Offset(0, px * 0.03))] : null,
  );
}

/// The inner space around the words: a pill gets room, bare words only enough for their shadow.
EdgeInsets studioTextPadding(StudioOverlay o, double px) =>
    o.background != null ? EdgeInsets.symmetric(horizontal: px * 0.45, vertical: px * 0.22) : EdgeInsets.all(px * 0.14);

TextPainter studioTextPainter(StudioOverlay o, double px, double maxWidth) => TextPainter(
      text: TextSpan(text: o.text, style: studioTextStyle(o, px)),
      textAlign: TextAlign.center,
      textDirection: o.rtl ? TextDirection.rtl : TextDirection.ltr,
    )..layout(maxWidth: math.max(1, maxWidth));

/// The text overlay as a PNG at the video's size ([frameW] × [frameH] px) and its width as a share of the frame.
Future<({Uint8List png, double w})> studioRasterText(StudioOverlay o, {required double frameW, required double frameH}) async {
  final px = o.size * frameH;
  final pad = studioTextPadding(o, px);
  final tp = studioTextPainter(o, px, frameW * studioTextMaxWidth - pad.horizontal);
  final w = (tp.width + pad.horizontal).ceil(), h = (tp.height + pad.vertical).ceil();
  final rec = ui.PictureRecorder();
  final canvas = Canvas(rec, Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()));
  if (o.background != null) {
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()), Radius.circular(px * 0.32)), Paint()..color = Color(o.background!));
  }
  tp.paint(canvas, Offset(pad.left, pad.top));
  final img = await rec.endRecording().toImage(math.max(1, w), math.max(1, h));
  final data = await img.toByteData(format: ui.ImageByteFormat.png);
  img.dispose();
  return (png: data!.buffer.asUint8List(), w: w / frameW);
}

/// The text box as a widget at a letter height of [px] (the preview).
class StudioTextBox extends StatelessWidget {
  const StudioTextBox({super.key, required this.overlay, required this.px, required this.maxWidth});
  final StudioOverlay overlay;
  final double px;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final o = overlay;
    final pad = studioTextPadding(o, px);
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: math.max(1, maxWidth)),
      child: Container(
        padding: pad,
        decoration: o.background == null ? null : BoxDecoration(color: Color(o.background!), borderRadius: BorderRadius.circular(px * 0.32)),
        child: Text(
          o.text,
          textAlign: TextAlign.center,
          textDirection: o.rtl ? TextDirection.rtl : TextDirection.ltr,
          textScaler: TextScaler.noScaling,
          style: studioTextStyle(o, px),
        ),
      ),
    );
  }
}

/// Puts its child's CENTRE at [center], loosely constrained to [maxWidth].
class _CenterAt extends SingleChildLayoutDelegate {
  _CenterAt(this.center, this.maxWidth);
  final Offset center;
  final double maxWidth;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) => BoxConstraints(maxWidth: maxWidth, maxHeight: constraints.maxHeight * 2);

  @override
  Offset getPositionForChild(Size size, Size childSize) => center - Offset(childSize.width / 2, childSize.height / 2);

  @override
  bool shouldRelayout(covariant _CenterAt o) => o.center != center || o.maxWidth != maxWidth;
}

/// The overlays over a frame of the video (the layer is exactly the picture's box).
class StudioOverlayLayer extends StatefulWidget {
  const StudioOverlayLayer({
    super.key,
    required this.edit,
    required this.now,
    this.selected,
    this.images = const {},
    this.editing = true,
    this.onSelect,
    this.onMove,
    this.onMoveEnd,
    this.onScale,
    this.onScaleEnd,
    this.onTapEmpty,
  });

  final StudioEdit edit;

  /// The playhead (output seconds).
  final double now;
  final String? selected;

  /// Picture overlays' bytes by asset id.
  final Map<String, Uint8List> images;

  /// Off while a job runs: drawn, not draggable.
  final bool editing;
  final ValueChanged<String?>? onSelect;
  final void Function(String id, double x, double y)? onMove;
  final ValueChanged<String>? onMoveEnd;

  /// The selected overlay's size × [factor] since the drag began (a picture's width, a text's letter height).
  final void Function(String id, double factor)? onScale;
  final ValueChanged<String>? onScaleEnd;
  final VoidCallback? onTapEmpty;

  @override
  State<StudioOverlayLayer> createState() => _StudioOverlayLayerState();
}

class _StudioOverlayLayerState extends State<StudioOverlayLayer> {
  Offset? _grabCentre; // the overlay's centre (px) when the drag began
  Offset _dragged = Offset.zero;
  double? _scaleFrom; // distance from the centre when a resize began
  bool _guideX = false, _guideY = false;

  @override
  Widget build(BuildContext context) {
    final w = widget;
    final sel = w.selected;
    final c = context.colors;
    return LayoutBuilder(builder: (context, box) {
      final fw = box.maxWidth, fh = box.maxHeight;
      if (!fw.isFinite || !fh.isFinite || fw <= 0 || fh <= 0) return const SizedBox.shrink();
      final children = <Widget>[
        Positioned.fill(
          child: GestureDetector(behavior: HitTestBehavior.translucent, onTap: w.onTapEmpty),
        ),
      ];
      for (final o in w.edit.overlays) {
        final span = w.edit.overlayOut(o);
        if (span == null) continue;
        final isSel = o.id == sel;
        final look = studioOverlayLook(o, span.$1, span.$2, w.now);
        if (look == null && !isSel) continue;
        // the selected one is never invisible while it is being placed (in its entrance / outside its time)
        final l0 = look ?? const StudioLook(opacity: 0.35);
        final l = isSel && l0.opacity < 0.35 ? StudioLook(opacity: 0.35, dx: l0.dx, dy: l0.dy, scale: l0.scale, reveal: math.max(l0.reveal, 0.35)) : l0;
        final centre = Offset((o.x + l.dx) * fw, (o.y + l.dy) * fh);
        Widget body;
        if (o.isText) {
          final px = o.size * fh;
          body = StudioTextBox(overlay: o, px: px, maxWidth: fw * studioTextMaxWidth);
          if (l.reveal < 1) {
            body = ClipRect(
              child: Align(
                alignment: o.rtl ? Alignment.centerRight : Alignment.centerLeft,
                widthFactor: math.max(0.0001, l.reveal),
                child: body,
              ),
            );
          }
        } else {
          final bytes = o.asset == null ? null : w.images[o.asset];
          final iw = o.w * fw;
          body = SizedBox(
            width: iw,
            height: iw * o.aspect,
            child: bytes == null
                ? DecoratedBox(decoration: BoxDecoration(color: c.onHero.withValues(alpha: 0.12), border: Border.all(color: c.onHeroFaint)))
                : Image.memory(bytes, fit: BoxFit.fill, gaplessPlayback: true, filterQuality: FilterQuality.medium),
          );
        }
        body = Opacity(opacity: l.opacity.clamp(0.0, 1.0), child: Transform.scale(scale: l.scale, child: body));
        if (isSel && w.editing) {
          body = Stack(clipBehavior: Clip.none, children: [
            DecoratedBox(
              position: DecorationPosition.foreground,
              decoration: BoxDecoration(border: Border.all(color: c.onHero, width: 1.5), borderRadius: BorderRadius.circular(4)),
              child: body,
            ),
            Positioned(
              right: -18,
              bottom: -18,
              child: Semantics(
                label: o.isText ? t('حجم النص', 'Text size') : t('حجم الصورة', 'Picture size'),
                child: GestureDetector(
                  key: ValueKey('studio.overlay.resize.${o.id}'),
                  behavior: HitTestBehavior.opaque,
                  onPanStart: (d) {
                    final rb = context.findRenderObject() as RenderBox?;
                    final local = rb?.globalToLocal(d.globalPosition) ?? Offset.zero;
                    _scaleFrom = math.max(8, (local - centre).distance);
                  },
                  onPanUpdate: (d) {
                    final rb = context.findRenderObject() as RenderBox?;
                    final local = rb?.globalToLocal(d.globalPosition) ?? Offset.zero;
                    if (_scaleFrom != null) w.onScale?.call(o.id, math.max(8, (local - centre).distance) / _scaleFrom!);
                  },
                  onPanEnd: (_) {
                    _scaleFrom = null;
                    w.onScaleEnd?.call(o.id);
                  },
                  child: SizedBox(
                    width: 36,
                    height: 36,
                    child: Center(
                      child: Container(
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(color: c.onHero, shape: BoxShape.circle, boxShadow: [BoxShadow(color: c.heroShade.withValues(alpha: 0.5), blurRadius: 4)]),
                        child: Icon(Icons.open_in_full_rounded, size: 11, color: c.heroShade),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ]);
        }
        body = GestureDetector(
          key: ValueKey('studio.overlay.${o.id}'),
          behavior: HitTestBehavior.opaque,
          onTap: w.editing ? () => w.onSelect?.call(o.id) : null,
          onPanStart: !w.editing
              ? null
              : (_) {
                  w.onSelect?.call(o.id);
                  _grabCentre = Offset(o.x * fw, o.y * fh);
                  _dragged = Offset.zero;
                },
          onPanUpdate: !w.editing
              ? null
              : (d) {
                  if (_grabCentre == null) return;
                  _dragged += d.delta;
                  var c = _grabCentre! + _dragged;
                  // the centre lines pull a little: a text lands exactly in the middle
                  final gx = (c.dx - fw / 2).abs() < fw * 0.015, gy = (c.dy - fh / 2).abs() < fh * 0.015;
                  if (gx) c = Offset(fw / 2, c.dy);
                  if (gy) c = Offset(c.dx, fh / 2);
                  if (gx != _guideX || gy != _guideY) {
                    setState(() {
                      _guideX = gx;
                      _guideY = gy;
                    });
                  }
                  w.onMove?.call(o.id, (c.dx / fw).clamp(0.0, 1.0), (c.dy / fh).clamp(0.0, 1.0));
                },
          onPanEnd: !w.editing
              ? null
              : (_) {
                  _grabCentre = null;
                  setState(() => _guideX = _guideY = false);
                  w.onMoveEnd?.call(o.id);
                },
          child: body,
        );
        children.add(Positioned.fill(child: CustomSingleChildLayout(delegate: _CenterAt(centre, fw * 1.2), child: body)));
      }
      if (_guideX) children.add(Positioned(left: fw / 2 - 0.5, top: 0, bottom: 0, child: IgnorePointer(child: ColoredBox(color: c.warning, child: const SizedBox(width: 1)))));
      if (_guideY) children.add(Positioned(top: fh / 2 - 0.5, left: 0, right: 0, child: IgnorePointer(child: ColoredBox(color: c.warning, child: const SizedBox(height: 1)))));
      return Stack(clipBehavior: Clip.hardEdge, children: children);
    });
  }
}
