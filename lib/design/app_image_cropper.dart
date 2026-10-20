// lib/design/app_image_cropper.dart
//
// ONE image cropper for the whole app (avatars, course covers, organization logos, announcement images …).
// Pure Flutter — no native setup, works on Android, iOS and web:
//   • pinch / drag / slider to zoom and position            • rotate 90°
//   • shape: square · circle (transparent corners) · wide 16:9
//   • output size: small 512 · medium 1024 · high 2048 px   → smaller, faster uploads ("reduce quality")
//
//   final bytes = await showAppImageCropper(context, original, shape: CropShape.circle);
//   if (bytes != null) upload(bytes);          // PNG
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/utils/helpers.dart';

enum CropShape { square, circle, wide }

String _t(String ar, String en) => AppConfig.lang == 'ar' ? ar : en;

Future<Uint8List?> showAppImageCropper(BuildContext context, Uint8List bytes,
    {CropShape shape = CropShape.square, bool allowShapeChange = true, bool allowOriginal = true}) {
  return Navigator.of(context).push<Uint8List>(MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => Directionality(
      textDirection: Helpers.pageDirection,
      child: _CropperPage(bytes: bytes, initial: shape, allowShapeChange: allowShapeChange, allowOriginal: allowOriginal),
    ),
  ));
}

/// Crop with the file name kept consistent: a cropped result is PNG ("photo.png"); "Use original" keeps the
/// original bytes AND name (format unchanged). null = cancelled.
Future<({Uint8List bytes, String name})?> cropImageWithName(BuildContext context, Uint8List bytes, String name,
    {CropShape shape = CropShape.square}) async {
  final out = await showAppImageCropper(context, bytes, shape: shape);
  if (out == null) return null;
  if (identical(out, bytes)) return (bytes: bytes, name: name);
  final base = name.contains('.') ? name.substring(0, name.lastIndexOf('.')) : name;
  return (bytes: out, name: '$base.png');
}

class _CropperPage extends StatefulWidget {
  const _CropperPage({required this.bytes, required this.initial, required this.allowShapeChange, required this.allowOriginal});
  final Uint8List bytes;
  final CropShape initial;
  final bool allowShapeChange, allowOriginal;

  @override
  State<_CropperPage> createState() => _CropperPageState();
}

class _CropperPageState extends State<_CropperPage> {
  final _boundary = GlobalKey();
  final _tc = TransformationController();
  late CropShape _shape = widget.initial;
  int _turns = 0;
  int _size = 1024;
  double _zoom = 1;
  bool _busy = false;

  @override
  void dispose() {
    _tc.dispose();
    super.dispose();
  }

  void _setZoom(double z, Size frame) {
    final c = Offset(frame.width / 2, frame.height / 2);
    _tc.value = Matrix4.identity()
      ..translate(c.dx, c.dy)
      ..scale(z)
      ..translate(-c.dx, -c.dy);
    setState(() => _zoom = z);
  }

  Future<void> _done(Size frame) async {
    setState(() => _busy = true);
    try {
      final ro = _boundary.currentContext?.findRenderObject();
      if (ro is! RenderRepaintBoundary) return;
      final ratio = _size / frame.width;
      final img = await ro.toImage(pixelRatio: ratio);
      final data = await img.toByteData(format: ui.ImageByteFormat.png);
      if (data != null && mounted) Navigator.pop(context, data.buffer.asUint8List());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: const Color(0xFF0B0F0E),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: Text(_t('تعديل الصورة', 'Edit photo'), style: const TextStyle(fontFamily: 'tajawal', fontWeight: FontWeight.w800)),
        actions: [
          // backgrounds, signatures, documents … sometimes must stay exactly as they are
          if (widget.allowOriginal)
            TextButton(
              onPressed: () => Navigator.pop(context, widget.bytes),
              child: Text(_t('استخدام الأصل', 'Use original'),
                  style: const TextStyle(fontFamily: 'tajawal', color: Colors.white, fontWeight: FontWeight.w700)),
            ),
          IconButton(
            tooltip: _t('تدوير', 'Rotate'),
            onPressed: () => setState(() => _turns = (_turns + 1) % 4),
            icon: const Icon(Icons.rotate_90_degrees_ccw_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(builder: (context, box) {
          final side = (box.maxWidth < box.maxHeight - 220 ? box.maxWidth : box.maxHeight - 220) * 0.86;
          final frame = _shape == CropShape.wide ? Size(side, side * 9 / 16) : Size(side, side);
          Widget content = SizedBox(
            width: frame.width,
            height: frame.height,
            child: InteractiveViewer(
              transformationController: _tc,
              minScale: 1,
              maxScale: 6,
              onInteractionUpdate: (_) => setState(() => _zoom = _tc.value.getMaxScaleOnAxis()),
              child: RotatedBox(
                quarterTurns: _turns,
                child: Image.memory(widget.bytes, width: frame.width, height: frame.height, fit: BoxFit.cover),
              ),
            ),
          );
          content = _shape == CropShape.circle ? ClipOval(child: content) : ClipRRect(borderRadius: BorderRadius.circular(4), child: content);
          return Column(children: [
            Expanded(
              child: Center(
                child: Stack(alignment: Alignment.center, children: [
                  RepaintBoundary(key: _boundary, child: content),
                  IgnorePointer(
                    child: Container(
                      width: frame.width,
                      height: frame.height,
                      decoration: BoxDecoration(
                        shape: _shape == CropShape.circle ? BoxShape.circle : BoxShape.rectangle,
                        border: Border.all(color: Colors.white.withValues(alpha: 0.85), width: 2),
                      ),
                    ),
                  ),
                ]),
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
              decoration: BoxDecoration(
                color: c.cardBg,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Row(children: [
                  Icon(Icons.zoom_out_rounded, color: c.textLight),
                  Expanded(
                    child: Slider(value: _zoom.clamp(1, 6), min: 1, max: 6, onChanged: (v) => _setZoom(v, frame)),
                  ),
                  Icon(Icons.zoom_in_rounded, color: c.textLight),
                ]),
                if (widget.allowShapeChange)
                  Wrap(spacing: 8, children: [
                    for (final (s, label, icon) in [
                      (CropShape.square, _t('مربع', 'Square'), Icons.crop_square_rounded),
                      (CropShape.circle, _t('دائري', 'Circle'), Icons.circle_outlined),
                      (CropShape.wide, _t('عريض', 'Wide'), Icons.crop_16_9_rounded),
                    ])
                      ChoiceChip(
                        avatar: Icon(icon, size: 16),
                        label: Text(label, style: const TextStyle(fontFamily: 'tajawal')),
                        selected: _shape == s,
                        onSelected: (_) => setState(() {
                          _shape = s;
                          _tc.value = Matrix4.identity();
                          _zoom = 1;
                        }),
                      ),
                  ]),
                const SizedBox(height: 6),
                Wrap(spacing: 8, children: [
                  for (final (px, label) in [
                    (512, _t('صغير', 'Small')),
                    (1024, _t('متوسط', 'Medium')),
                    (2048, _t('عالي', 'High')),
                  ])
                    ChoiceChip(
                      label: Text('$label · $px', style: const TextStyle(fontFamily: 'tajawal')),
                      selected: _size == px,
                      onSelected: (_) => setState(() => _size = px),
                    ),
                ]),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _busy ? null : () => _done(frame),
                    icon: _busy
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.check_rounded),
                    label: Text(_t('استخدام الصورة', 'Use photo')),
                  ),
                ),
              ]),
            ),
          ]);
        }),
      ),
    );
  }
}
