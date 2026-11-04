// The blank sheet with its boxes on top: tap a box to select it, drag it to move, drag a handle to resize, drag on
// empty space to draw a new one; pinch / wheel to zoom, the hand tool (or two fingers) to pan. Boxes live in page
// coordinates 0..1, so the zoom never changes what is saved. Mouse and touch work the same; the page above owns
// the keyboard (Delete, Ctrl+Z).
import 'dart:typed_data';

import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_tokens.dart';

import '../../../../admin/admin_common.dart' show t;
import '../mark_templates_api.dart';
import 'mark_editor_model.dart';
import 'mark_template_common.dart';

/// The caption on a box: what it is, in a few characters.
String fieldCaption(MarkField f) {
  switch (f.type) {
    case FieldType.identifier:
      return identifierSourceLabel(f.source);
    case FieldType.questionMark:
      return t('س${f.questionNo ?? '?'} · ${f.max == null ? '?' : numText(f.max!)}', 'Q${f.questionNo ?? '?'} · ${f.max == null ? '?' : numText(f.max!)}');
    case FieldType.total:
      return t('المجموع ${f.max == null ? '?' : numText(f.max!)}', 'Total ${f.max == null ? '?' : numText(f.max!)}');
    case FieldType.answerRow:
      return t('إجابة ${f.questionNo ?? '?'}', 'Answer ${f.questionNo ?? '?'}');
    case FieldType.unset:
      return '?';
  }
}

enum _Drag { none, move, resize, draw }

enum _Handle { tl, t, tr, r, br, b, bl, l }

class MarkCanvas extends StatefulWidget {
  const MarkCanvas({super.key, required this.model, required this.aspect, this.image, this.onFieldTap, this.readOnly = false});

  final MarkEditorModel model;

  /// width / height of the page.
  final double aspect;
  final Uint8List? image;

  /// A box was tapped (null = empty space): the phone opens the box's sheet.
  final ValueChanged<String?>? onFieldTap;
  final bool readOnly;

  @override
  State<MarkCanvas> createState() => _MarkCanvasState();
}

class _MarkCanvasState extends State<MarkCanvas> {
  final _tc = TransformationController();
  bool _panTool = false;
  Size _size = Size.zero;

  _Drag _drag = _Drag.none;
  _Handle? _handle;
  String? _dragId;
  Rect _startBox = Rect.zero;
  Offset _startPoint = Offset.zero;
  bool _moved = false;

  MarkEditorModel get m => widget.model;
  double get _scale => _tc.value.getMaxScaleOnAxis();

  @override
  void dispose() {
    _tc.dispose();
    super.dispose();
  }

  Offset _norm(Offset local) => Offset(_size.width <= 0 ? 0 : local.dx / _size.width, _size.height <= 0 ? 0 : local.dy / _size.height);

  Map<_Handle, Offset> _handles(Rect b) => {
        _Handle.tl: b.topLeft,
        _Handle.t: b.topCenter,
        _Handle.tr: b.topRight,
        _Handle.r: b.centerRight,
        _Handle.br: b.bottomRight,
        _Handle.b: b.bottomCenter,
        _Handle.bl: b.bottomLeft,
        _Handle.l: b.centerLeft,
      };

  _Handle? _hitHandle(Offset p) {
    final sel = m.selected;
    if (sel == null) return null;
    final rx = 20 / _scale / _size.width;
    final ry = 20 / _scale / _size.height;
    _Handle? best;
    var bestD = double.infinity;
    for (final e in _handles(sel.box).entries) {
      final dx = (e.value.dx - p.dx).abs() / rx;
      final dy = (e.value.dy - p.dy).abs() / ry;
      if (dx <= 1 && dy <= 1 && dx + dy < bestD) {
        best = e.key;
        bestD = dx + dy;
      }
    }
    return best;
  }

  void _panStart(DragStartDetails d) {
    final p = _norm(d.localPosition);
    _moved = false;
    _startPoint = p;
    final h = _hitHandle(p);
    if (h != null) {
      _drag = _Drag.resize;
      _handle = h;
      _dragId = m.selectedId;
      _startBox = m.selected!.box;
      m.beginDrag();
      return;
    }
    final id = m.hit(p);
    if (id != null) {
      m.select(id);
      _drag = _Drag.move;
      _dragId = id;
      _startBox = m.spec.field(id)!.box;
      m.beginDrag();
      return;
    }
    _drag = _Drag.draw;
    _dragId = null;
  }

  void _panUpdate(DragUpdateDetails d) {
    if (_drag == _Drag.none) return;
    final p = _norm(d.localPosition);
    final delta = p - _startPoint;
    switch (_drag) {
      case _Drag.move:
        _moved = true;
        m.dragBox(_dragId!, _startBox.shift(delta));
      case _Drag.resize:
        _moved = true;
        m.dragBox(_dragId!, _resized(_startBox, _handle!, delta));
      case _Drag.draw:
        final r = Rect.fromPoints(_startPoint, Offset(p.dx.clamp(0.0, 1.0), p.dy.clamp(0.0, 1.0)));
        if (_dragId == null) {
          if (r.width < 0.006 && r.height < 0.006) return;
          _dragId = m.addBox(r);
          _moved = true;
        } else {
          m.dragBox(_dragId!, r);
        }
      case _Drag.none:
        break;
    }
  }

  Rect _resized(Rect b, _Handle h, Offset d) {
    var l = b.left, tp = b.top, r = b.right, bt = b.bottom;
    switch (h) {
      case _Handle.tl || _Handle.l || _Handle.bl:
        l += d.dx;
      case _Handle.tr || _Handle.r || _Handle.br:
        r += d.dx;
      default:
        break;
    }
    switch (h) {
      case _Handle.tl || _Handle.t || _Handle.tr:
        tp += d.dy;
      case _Handle.bl || _Handle.b || _Handle.br:
        bt += d.dy;
      default:
        break;
    }
    // dragged past the opposite edge → the box flips, never goes negative
    return Rect.fromLTRB(l < r ? l : r, tp < bt ? tp : bt, l < r ? r : l, tp < bt ? bt : tp);
  }

  void _panEnd([Object? _]) {
    if (_drag == _Drag.move || _drag == _Drag.resize) m.endDrag(changed: _moved);
    _drag = _Drag.none;
    _dragId = null;
  }

  void _tapUp(TapUpDetails d) {
    final p = _norm(d.localPosition);
    final id = _hitHandle(p) != null ? m.selectedId : m.hit(p);
    m.select(id);
    widget.onFieldTap?.call(id);
  }

  void _zoom(double factor) {
    final c = Offset(_size.width / 2, _size.height / 2);
    final next = (_scale * factor).clamp(0.5, 8.0) / _scale;
    final mat = Matrix4.identity()
      ..translateByDouble(c.dx, c.dy, 0, 1)
      ..scaleByDouble(next, next, 1, 1)
      ..translateByDouble(-c.dx, -c.dy, 0, 1);
    _tc.value = mat * _tc.value;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final editing = !_panTool && !widget.readOnly;
    return LayoutBuilder(builder: (context, box) {
      final maxW = box.maxWidth.isFinite ? box.maxWidth : 600.0;
      final maxH = box.maxHeight.isFinite ? box.maxHeight : 800.0;
      var w = maxW - AppSpace.md * 2;
      var h = w / widget.aspect;
      if (h > maxH - AppSpace.md * 2) {
        h = maxH - AppSpace.md * 2;
        w = h * widget.aspect;
      }
      if (w < 40 || h < 40) {
        w = 40;
        h = 40 / widget.aspect;
      }
      _size = Size(w, h);
      return Stack(children: [
        Positioned.fill(
          child: ColoredBox(
            color: c.inputBg,
            child: InteractiveViewer(
              transformationController: _tc,
              minScale: 0.5,
              maxScale: 8,
              panEnabled: !editing,
              boundaryMargin: const EdgeInsets.all(240),
              constrained: false,
              child: SizedBox(
                width: maxW,
                height: maxH,
                child: Center(
                  child: Directionality(
                    textDirection: TextDirection.ltr,
                    child: SizedBox(width: w, height: h, child: _page(context, editing)),
                  ),
                ),
              ),
            ),
          ),
        ),
        PositionedDirectional(
          top: AppSpace.xs,
          end: AppSpace.xs,
          child: _Tools(
            panTool: _panTool,
            onPanTool: (v) => setState(() => _panTool = v),
            onZoom: _zoom,
            onReset: () => _tc.value = Matrix4.identity(),
          ),
        ),
      ]);
    });
  }

  Widget _page(BuildContext context, bool editing) {
    final c = context.colors;
    final colors = {for (final ty in FieldType.values) ty: fieldColor(context, ty)};
    return DecoratedBox(
      decoration: BoxDecoration(color: c.cardBg, boxShadow: const [BoxShadow(blurRadius: 8, color: Color(0x33000000))]),
      child: Stack(clipBehavior: Clip.none, children: [
        Positioned.fill(
          child: widget.image == null
              ? const SizedBox()
              : Image.memory(widget.image!,
                  fit: BoxFit.fill,
                  gaplessPlayback: true,
                  semanticLabel: t('الورقة الفارغة', 'The blank sheet'),
                  errorBuilder: (_, _, _) => Center(child: Icon(Icons.broken_image_outlined, color: c.textMedium))),
        ),
        Positioned.fill(
          child: RepaintBoundary(
            child: CustomPaint(
              painter: _BoxPainter(m, _tc, colors, c.danger, c.cardBg),
            ),
          ),
        ),
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedBuilder(
              animation: Listenable.merge([m, _tc]),
              builder: (_, _) => Stack(clipBehavior: Clip.none, children: [
                for (final f in m.fields) _label(context, f, colors[f.type]!),
              ]),
            ),
          ),
        ),
        if (editing)
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              dragStartBehavior: DragStartBehavior.down,
              onTapUp: _tapUp,
              onPanStart: _panStart,
              onPanUpdate: _panUpdate,
              onPanEnd: _panEnd,
              onPanCancel: _panEnd,
            ),
          ),
      ]),
    );
  }

  Widget _label(BuildContext context, MarkField f, Color col) {
    final s = _scale;
    final selected = f.id == m.selectedId;
    final txt = fieldCaption(f);
    return Positioned(
      left: f.box.left * _size.width,
      bottom: (1 - f.box.top) * _size.height,
      child: Transform.scale(
        scale: 1 / s,
        alignment: Alignment.bottomLeft,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
          constraints: const BoxConstraints(maxWidth: 160),
          decoration: BoxDecoration(color: col.withValues(alpha: selected ? 1 : 0.85), borderRadius: BorderRadius.circular(4)),
          child: Text(txt, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10, height: 1.2, color: Colors.white, fontWeight: FontWeight.w600)),
        ),
      ),
    );
  }
}

class _Tools extends StatelessWidget {
  const _Tools({required this.panTool, required this.onPanTool, required this.onZoom, required this.onReset});
  final bool panTool;
  final ValueChanged<bool> onPanTool;
  final ValueChanged<double> onZoom;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget btn(IconData i, String tip, VoidCallback f, {bool on = false}) => IconButton(
          tooltip: tip,
          constraints: const BoxConstraints(minWidth: AppTouch.min, minHeight: AppTouch.min),
          onPressed: f,
          isSelected: on,
          icon: Icon(i, color: on ? c.primary : c.textDark),
        );
    return DecoratedBox(
      decoration: BoxDecoration(color: c.cardBg.withValues(alpha: 0.94), borderRadius: AppRadius.cardAll, border: Border.all(color: c.divider)),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        btn(Icons.edit_outlined, t('تحريك ورسم المربعات', 'Move and draw boxes'), () => onPanTool(false), on: !panTool),
        btn(Icons.pan_tool_alt_outlined, t('تحريك الصفحة', 'Pan the page'), () => onPanTool(true), on: panTool),
        btn(Icons.add_rounded, t('تكبير', 'Zoom in'), () => onZoom(1.4)),
        btn(Icons.remove_rounded, t('تصغير', 'Zoom out'), () => onZoom(1 / 1.4)),
        btn(Icons.fit_screen_outlined, t('ملاءمة الشاشة', 'Fit to screen'), onReset),
      ]),
    );
  }
}

class _BoxPainter extends CustomPainter {
  _BoxPainter(this.m, this.tc, this.colors, this.danger, this.halo) : super(repaint: Listenable.merge([m, tc]));
  final MarkEditorModel m;
  final TransformationController tc;
  final Map<FieldType, Color> colors;
  final Color danger;
  final Color halo;

  @override
  void paint(Canvas canvas, Size size) {
    final s = tc.value.getMaxScaleOnAxis();
    Rect px(Rect r) => Rect.fromLTWH(r.left * size.width, r.top * size.height, r.width * size.width, r.height * size.height);
    for (final f in m.fields) {
      final sel = f.id == m.selectedId;
      final col = colors[f.type]!;
      final bad = m.issuesOf(f.id).any((i) => i.error);
      final r = px(f.box);
      canvas.drawRect(r, Paint()..color = col.withValues(alpha: sel ? 0.30 : 0.16));
      canvas.drawRect(
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = (sel ? 2.4 : 1.4) / s
          ..color = bad ? danger : col,
      );
      for (final o in f.options) {
        canvas.drawRect(
          px(o.box).deflate(0.5 / s),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.8 / s
            ..color = col.withValues(alpha: 0.7),
        );
      }
    }
    final sel = m.selected;
    if (sel != null) {
      final hs = 9 / s;
      for (final p in [sel.box.topLeft, sel.box.topCenter, sel.box.topRight, sel.box.centerRight, sel.box.bottomRight, sel.box.bottomCenter, sel.box.bottomLeft, sel.box.centerLeft]) {
        final c = Offset(p.dx * size.width, p.dy * size.height);
        final rect = Rect.fromCenter(center: c, width: hs, height: hs);
        canvas.drawRect(rect, Paint()..color = colors[sel.type]!);
        canvas.drawRect(
          rect,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5 / s
            ..color = halo,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_BoxPainter old) => true;
}
