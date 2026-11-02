// The sheet with its boxes drawn on top (Example 3's step-through): the canonical preview image, every learned box
// faint, the current question's (or zone's) boxes highlighted and the rest of the page dimmed, the filled sample's
// marks in green. Zoom / pan through an InteractiveViewer (pinch on phones, wheel / drag on web and desktop, plus
// +/−/fit buttons); while editing, one finger or the mouse DRAGS a bubble (or the whole question) and the handle on
// the selected bubble RESIZES it — a drag that starts off a box still pans, because the box's own recognizer wins
// the arena only when the pointer went down on it.
//
// Plain values in (image bytes, the geometry, bubbles in mm), the change out as bubbles in mm (`onChanged`); every
// mm ↔ pixel step goes through SheetGeometry (omr_templates.dart), and pointer positions are read through the page's
// own RenderBox (`globalToLocal`), so the InteractiveViewer's zoom never skews a drag.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_tokens.dart';

import '../../../../admin/admin_common.dart' show t;
import 'omr_templates.dart';

class SheetOverlay extends StatefulWidget {
  const SheetOverlay({
    super.key,
    required this.image,
    required this.geometry,
    this.others = const [],
    this.current = const [],
    this.filled = const {},
    this.zoneMm,
    this.focusMm,
    this.editing = false,
    this.moveAll = false,
    this.selected,
    this.onSelect,
    this.onChanged,
    this.onChangeEnd,
    this.semanticLabel,
  });

  /// The preview PNG; null draws a plain page while it loads.
  final Uint8List? image;
  final SheetGeometry geometry;

  /// Every other learned box (drawn faint).
  final List<OmrBubble> others;

  /// The boxes of the current step (highlighted, editable).
  final List<OmrBubble> current;

  /// Labels of [current] the filled sample showed.
  final Set<String> filled;

  /// A zone to highlight (mm): the student ID grid, the model row.
  final Rect? zoneMm;

  /// What to zoom onto (mm); null shows the whole page. A new value animates there.
  final Rect? focusMm;
  final bool editing;

  /// Editing drags the whole set instead of one bubble.
  final bool moveAll;
  final int? selected;
  final ValueChanged<int>? onSelect;

  /// The current boxes after a drag / resize step (mm).
  final ValueChanged<List<OmrBubble>>? onChanged;
  final VoidCallback? onChangeEnd;
  final String? semanticLabel;

  @override
  State<SheetOverlay> createState() => SheetOverlayState();
}

class SheetOverlayState extends State<SheetOverlay> with SingleTickerProviderStateMixin {
  final _tc = TransformationController();
  final _pageKey = GlobalKey();
  late final AnimationController _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 320));
  Animation<Matrix4>? _tween;
  Size _viewport = Size.zero;
  Rect? _focusedOn;
  Size? _focusedSize;
  bool _placed = false;

  // drag state
  List<OmrBubble>? _dragStart;
  Offset? _dragOrigin;
  int? _dragIndex;
  bool _resizing = false;

  @override
  void initState() {
    super.initState();
    _anim.addListener(() {
      final tw = _tween;
      if (tw != null) _tc.value = tw.value;
    });
    _tc.addListener(_onTransform);
  }

  double _scale = 1;

  /// The current zoom (screen px per preview px).
  double get scale => _tc.value.getMaxScaleOnAxis();

  void _onTransform() {
    final s = _tc.value.getMaxScaleOnAxis();
    if ((s - _scale).abs() > 0.01) setState(() => _scale = s);
  }

  @override
  void dispose() {
    _tc.removeListener(_onTransform);
    _tc.dispose();
    _anim.dispose();
    super.dispose();
  }

  Matrix4 _target() {
    final g = widget.geometry;
    final f = widget.focusMm;
    if (f == null || _viewport.isEmpty) return g.fit(_viewport);
    // a phone fills most of its width with the step (bubbles ≥ 48 px apart); a wide window keeps the page around it
    final narrow = _viewport.width < 600;
    final fill = narrow ? (widget.zoneMm != null ? 0.62 : 0.72) : 0.4; // a zone (the ID grid) keeps clear of the zoom buttons
    return g.focusOn(g.rectToPreview(f), _viewport, fill: fill, maxScale: narrow ? 3.5 : 2.4);
  }

  void _focus({required bool animate}) {
    if (!mounted || _viewport.isEmpty) return;
    _focusedOn = widget.focusMm;
    _focusedSize = widget.geometry.size;
    final to = _target();
    final off = AppMotion.of(context).off;
    if (!animate || off) {
      _anim.stop();
      _tc.value = to;
      return;
    }
    _tween = Matrix4Tween(begin: _tc.value.clone(), end: to).animate(CurvedAnimation(parent: _anim, curve: AppMotion.emphasized));
    _anim
      ..reset()
      ..forward();
  }

  /// Zoom by [factor] around the viewport's centre (the +/− buttons).
  void zoomBy(double factor) {
    if (_viewport.isEmpty) return;
    final c = Offset(_viewport.width / 2, _viewport.height / 2);
    final fit = widget.geometry.fitScale(_viewport);
    final s = _tc.value.getMaxScaleOnAxis();
    final next = (s * factor).clamp(fit * 0.6, 8.0).toDouble();
    final f = next / s;
    final m = Matrix4.identity()
      ..translateByDouble(c.dx, c.dy, 0, 1)
      ..scaleByDouble(f, f, f, 1)
      ..translateByDouble(-c.dx, -c.dy, 0, 1);
    _anim.stop();
    _tc.value = m * _tc.value;
  }

  void fitPage() {
    _anim.stop();
    _tc.value = widget.geometry.fit(_viewport);
  }

  /// Back to the current step's zoom (after the person panned away).
  void refocus() => _focus(animate: true);

  Offset? _local(Offset global) {
    final box = _pageKey.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return null;
    return box.globalToLocal(global);
  }

  void _start(int? index, Offset global, {bool resize = false}) {
    final p = _local(global);
    if (p == null) return;
    _dragStart = List.of(widget.current);
    _dragOrigin = p;
    _dragIndex = index;
    _resizing = resize;
    if (index != null && index != widget.selected) widget.onSelect?.call(index);
  }

  void _update(Offset global) {
    final start = _dragStart, origin = _dragOrigin;
    final p = _local(global);
    if (start == null || origin == null || p == null) return;
    final g = widget.geometry;
    final i = _dragIndex;
    List<OmrBubble> next;
    if (_resizing && i != null) {
      next = [for (var k = 0; k < start.length; k++) k == i ? g.resizedTo(start[k], p) : start[k]];
    } else if (i == null) {
      next = g.movedAll(start, p - origin);
    } else {
      next = [for (var k = 0; k < start.length; k++) k == i ? g.moved(start[k], p - origin) : start[k]];
    }
    widget.onChanged?.call(next);
  }

  void _end() {
    if (_dragStart == null) return;
    _dragStart = null;
    _dragOrigin = null;
    _dragIndex = null;
    _resizing = false;
    widget.onChangeEnd?.call();
  }

  Widget _target2(Rect r, {required Key key, required int? index, bool resize = false, required MouseCursor cursor, String? label}) => Positioned.fromRect(
        key: key,
        rect: r,
        child: Semantics(
          label: label,
          button: true,
          child: MouseRegion(
            cursor: cursor,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              dragStartBehavior: DragStartBehavior.down, // the whole drag counts, touch slop included
              onTapDown: index == null ? null : (_) => widget.onSelect?.call(index),
              onPanStart: (d) => _start(index, d.globalPosition, resize: resize),
              onPanUpdate: (d) => _update(d.globalPosition),
              onPanEnd: (_) => _end(),
              onPanCancel: _end,
            ),
          ),
        ),
      );

  List<Widget> _editTargets() {
    final g = widget.geometry;
    final cur = widget.current;
    if (!widget.editing || cur.isEmpty) return const [];
    final s = math.max(_scale, 0.05);
    final minHit = AppTouch.min / s; // ≥ 48 logical px on screen at the current zoom
    if (widget.moveAll) {
      final u = g.unionRect(cur, padMm: 1)!;
      final grow = math.max(0.0, (minHit - u.shortestSide) / 2);
      return [_target2(u.inflate(grow), key: const ValueKey('omr.box.all'), index: null, cursor: SystemMouseCursors.move, label: t('اسحب لتحريك السؤال كله', 'Drag to move the whole question'))];
    }
    final order = [for (var i = 0; i < cur.length; i++) if (i != widget.selected) i, if (widget.selected != null && widget.selected! < cur.length) widget.selected!];
    final out = <Widget>[];
    for (final i in order) {
      final c = g.centreOf(cur[i]);
      final side = math.max(g.lenToPreview(cur[i].r) * 2 + 4, minHit);
      out.add(_target2(Rect.fromCenter(center: c, width: side, height: side),
          key: ValueKey('omr.box.$i'),
          index: i, cursor: SystemMouseCursors.move, label: t('الفقاعة ${cur[i].label} — اسحبها لتحريكها', 'Bubble ${cur[i].label} — drag to move it')));
    }
    final sel = widget.selected;
    if (sel != null && sel < cur.length) {
      final b = cur[sel];
      final h = handleCentre(g, b);
      final side = math.max(minHit * 0.9, 10.0);
      out.add(_target2(Rect.fromCenter(center: h, width: side, height: side),
          key: const ValueKey('omr.box.handle'),
          index: sel, resize: true, cursor: SystemMouseCursors.resizeLeftRight, label: t('اسحب لتغيير حجم الفقاعة ${b.label}', 'Drag to resize bubble ${b.label}')));
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final g = widget.geometry;
    return Semantics(
      label: widget.semanticLabel,
      image: true,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: ColoredBox(
          color: c.cardBg2,
          child: LayoutBuilder(builder: (context, box) {
            final vp = Size(box.maxWidth, box.maxHeight);
            if (vp != _viewport) {
              _viewport = vp;
              WidgetsBinding.instance.addPostFrameCallback((_) => _focus(animate: _placed));
              _placed = true;
            } else if ((_focusedOn != widget.focusMm || _focusedSize != g.size) && !_anim.isAnimating) {
              WidgetsBinding.instance.addPostFrameCallback((_) => _focus(animate: true));
            }
            final margin = math.max(vp.width, vp.height);
            return Stack(children: [
              Positioned.fill(
                child: InteractiveViewer(
                  transformationController: _tc,
                  constrained: false,
                  boundaryMargin: EdgeInsets.all(margin),
                  minScale: math.max(0.02, g.fitScale(vp) * 0.6),
                  maxScale: 8,
                  child: SizedBox(
                    key: _pageKey,
                    width: g.width,
                    height: g.height,
                    child: Stack(clipBehavior: Clip.none, children: [
                      Positioned.fill(
                        child: widget.image == null
                            ? ColoredBox(color: c.cardBg)
                            : Image.memory(widget.image!, fit: BoxFit.fill, gaplessPlayback: true, filterQuality: FilterQuality.medium),
                      ),
                      Positioned.fill(
                        child: IgnorePointer(
                          child: CustomPaint(
                            painter: SheetOverlayPainter(
                              geometry: g,
                              others: widget.others,
                              current: widget.current,
                              filled: widget.filled,
                              zoneMm: widget.zoneMm,
                              selected: widget.editing ? widget.selected : null,
                              editing: widget.editing,
                              moveAll: widget.moveAll,
                              scale: _scale,
                              primary: c.primary,
                              filledColor: c.success,
                              selectedColor: c.accent,
                              faint: c.textMedium,
                              scrim: c.charcoalDark,
                              ring: c.cardBg,
                            ),
                          ),
                        ),
                      ),
                      ..._editTargets(),
                    ]),
                  ),
                ),
              ),
              PositionedDirectional(
                end: AppSpace.xs,
                bottom: AppSpace.xs,
                child: _ZoomButtons(onIn: () => zoomBy(1.4), onOut: () => zoomBy(1 / 1.4), onFit: fitPage, onFocus: widget.focusMm == null ? null : refocus),
              ),
            ]);
          }),
        ),
      ),
    );
  }
}

/// Where the resize handle of [b] sits (preview px): on the circle, towards the reading direction's end.
Offset handleCentre(SheetGeometry g, OmrBubble b) => g.centreOf(b) + Offset(g.lenToPreview(b.r), 0);

class _ZoomButtons extends StatelessWidget {
  const _ZoomButtons({required this.onIn, required this.onOut, required this.onFit, this.onFocus});
  final VoidCallback onIn;
  final VoidCallback onOut;
  final VoidCallback onFit;
  final VoidCallback? onFocus;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget b(IconData icon, String tip, VoidCallback? on, String key) => IconButton(
          key: ValueKey('omr.zoom.$key'),
          tooltip: tip,
          onPressed: on,
          constraints: const BoxConstraints.tightFor(width: AppTouch.min, height: AppTouch.min),
          icon: Icon(icon, size: 22, color: c.textDark),
        );
    return Material(
      color: c.cardBg,
      elevation: 2,
      shadowColor: Colors.black26,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.card), side: BorderSide(color: c.divider)),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        b(Icons.add_rounded, t('تكبير', 'Zoom in'), onIn, 'in'),
        b(Icons.remove_rounded, t('تصغير', 'Zoom out'), onOut, 'out'),
        b(Icons.fit_screen_rounded, t('الصفحة كاملة', 'Whole page'), onFit, 'fit'),
        if (onFocus != null) b(Icons.center_focus_strong_rounded, t('العودة إلى الخطوة', 'Back to this step'), onFocus, 'focus'),
      ]),
    );
  }
}

/// Paints the boxes in preview pixels (the InteractiveViewer scales them); line widths are divided by [scale] so
/// they keep their on-screen thickness at every zoom.
class SheetOverlayPainter extends CustomPainter {
  SheetOverlayPainter({
    required this.geometry,
    required this.others,
    required this.current,
    required this.filled,
    required this.zoneMm,
    required this.selected,
    required this.editing,
    required this.moveAll,
    required this.scale,
    required this.primary,
    required this.filledColor,
    required this.selectedColor,
    required this.faint,
    required this.scrim,
    required this.ring,
  });

  final SheetGeometry geometry;
  final List<OmrBubble> others;
  final List<OmrBubble> current;
  final Set<String> filled;
  final Rect? zoneMm;
  final int? selected;
  final bool editing;
  final bool moveAll;
  final double scale;
  final Color primary;
  final Color filledColor;
  final Color selectedColor;
  final Color faint;

  /// Dims the page around the step (dark ink at a low alpha: the page is white paper in both themes).
  final Color scrim;

  /// The resize handle's ring.
  final Color ring;

  @override
  void paint(Canvas canvas, Size size) {
    final g = geometry;
    final s = math.max(scale, 0.05);
    double px(double screen) => screen / s;
    final focus = zoneMm != null ? g.rectToPreview(zoneMm!) : (current.isNotEmpty ? g.unionRect(current) : null);

    // the rest of the page, dimmed around the step
    if (focus != null) {
      final rr = RRect.fromRectAndRadius(focus, Radius.circular(px(8)));
      final path = Path()
        ..fillType = PathFillType.evenOdd
        ..addRect(Offset.zero & size)
        ..addRRect(rr);
      canvas.drawPath(path, Paint()..color = scrim.withValues(alpha: 0.2));
    }

    final faintPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = px(1)
      ..color = faint.withValues(alpha: 0.45);
    for (final b in others) {
      canvas.drawCircle(g.centreOf(b), g.lenToPreview(b.r), faintPaint);
    }

    if (zoneMm != null) {
      final z = RRect.fromRectAndRadius(g.rectToPreview(zoneMm!), Radius.circular(px(8)));
      canvas.drawRRect(z, Paint()..color = primary.withValues(alpha: 0.08));
      canvas.drawRRect(
          z,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = px(2)
            ..color = primary);
    }

    if (focus != null && current.isNotEmpty && zoneMm == null) {
      final rr = RRect.fromRectAndRadius(focus, Radius.circular(px(8)));
      canvas.drawRRect(
          rr,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = px(editing && moveAll ? 3 : 2)
            ..color = (editing && moveAll ? selectedColor : primary).withValues(alpha: 0.9));
    }

    for (var i = 0; i < current.length; i++) {
      final b = current[i];
      final c = g.centreOf(b);
      final r = g.lenToPreview(b.r);
      final isFilled = filled.contains(b.label);
      if (isFilled) canvas.drawCircle(c, r, Paint()..color = filledColor.withValues(alpha: 0.32));
      canvas.drawCircle(
          c,
          r,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = px(i == selected ? 3 : 2)
            ..color = i == selected ? selectedColor : (isFilled ? filledColor : primary));
      if (editing) canvas.drawCircle(c, px(2), Paint()..color = i == selected ? selectedColor : primary);
    }

    final sel = selected;
    if (editing && !moveAll && sel != null && sel < current.length) {
      final h = handleCentre(g, current[sel]);
      canvas.drawCircle(h, px(7), Paint()..color = selectedColor);
      canvas.drawCircle(
          h,
          px(7),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = px(2)
            ..color = ring);
    }
  }

  @override
  bool shouldRepaint(covariant SheetOverlayPainter o) =>
      o.scale != scale ||
      o.selected != selected ||
      o.editing != editing ||
      o.moveAll != moveAll ||
      o.zoneMm != zoneMm ||
      !sameBubbles(o.current, current) ||
      o.others.length != others.length ||
      o.filled.length != filled.length ||
      !o.filled.containsAll(filled) ||
      o.primary != primary;
}
