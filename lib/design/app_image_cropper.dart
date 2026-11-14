// lib/design/app_image_cropper.dart
//
// ONE image cropper for the whole app (avatars, course covers, organization logos, announcement images …).
// Pure Flutter — no native setup, works on Android, iOS and web:
//   • pinch / drag / slider to zoom and position            • rotate 90°
//   • shape: square · circle (transparent corners) · wide 16:9
//   • output size: small 512 · medium 1024 · high 2048 px   → smaller, faster uploads ("reduce quality")
//   • background: remove it on the device (no model, no server: D-510) and put a colour / gradient behind the subject
//     (app_image_background.dart)
//
//   final bytes = await showAppImageCropper(context, original, shape: CropShape.circle);
//   if (bytes != null) upload(bytes);          // PNG
//
// [allowBackground] false hides the Background tool: documents, scans and anything that must stay as photographed.
// [allowTransparent] false keeps colours and gradients but offers no transparent result: where the server flattens the
// upload to JPEG, so a transparent corner would turn black or white behind the person's back.
//
// Coordinates: the Background tab draws on the picture through a Listener over the frame (a tap = pick, a drag = brush);
// [bgFramePointToSource] turns a point of the frame into a pixel of the picture whatever the zoom and rotation are.
library;

import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind, kPrimaryButton, kTouchSlop;
import 'package:flutter/rendering.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/utils/helpers.dart';
import 'package:flutter_education_app/core/display/app_fonts.dart';

import 'app_buttons.dart';
import 'app_image_background.dart';
import 'image_background_engine.dart' show bgFramePointToSource, bgSourcePerFramePixel;
import 'app_kit.dart' show AppSheetContent, showAppSheet;
import 'app_notice.dart';
import 'app_tabs.dart';
import 'app_tokens.dart';
import 'studio/studio_props.dart' show StudioColorField;

enum CropShape { square, circle, wide }

String _t(String ar, String en) => AppConfig.lang == 'ar' ? ar : en;

Future<Uint8List?> showAppImageCropper(BuildContext context, Uint8List bytes,
    {CropShape shape = CropShape.square,
    bool allowShapeChange = true,
    bool allowOriginal = true,
    bool allowBackground = true,
    bool allowTransparent = true}) {
  return Navigator.of(context).push<Uint8List>(MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => Directionality(
      textDirection: Helpers.pageDirection,
      child: _CropperPage(
        bytes: bytes,
        initial: shape,
        allowShapeChange: allowShapeChange,
        allowOriginal: allowOriginal,
        allowBackground: allowBackground,
        allowTransparent: allowTransparent,
      ),
    ),
  ));
}

/// Crop with the file name kept consistent: a cropped result is PNG ("photo.png"); "Use original" keeps the
/// original bytes AND name (format unchanged). null = cancelled.
Future<({Uint8List bytes, String name})?> cropImageWithName(BuildContext context, Uint8List bytes, String name,
    {CropShape shape = CropShape.square, bool allowBackground = true, bool allowTransparent = true}) async {
  final out = await showAppImageCropper(context, bytes, shape: shape, allowBackground: allowBackground, allowTransparent: allowTransparent);
  if (out == null) return null;
  if (identical(out, bytes)) return (bytes: bytes, name: name);
  final base = name.contains('.') ? name.substring(0, name.lastIndexOf('.')) : name;
  return (bytes: out, name: '$base.png');
}

class _CropperPage extends StatefulWidget {
  const _CropperPage({
    required this.bytes,
    required this.initial,
    required this.allowShapeChange,
    required this.allowOriginal,
    required this.allowBackground,
    required this.allowTransparent,
  });
  final Uint8List bytes;
  final CropShape initial;
  final bool allowShapeChange, allowOriginal, allowBackground, allowTransparent;

  @override
  State<_CropperPage> createState() => _CropperPageState();
}

class _CropperPageState extends State<_CropperPage> with TickerProviderStateMixin {
  /// From this width the tools sit beside the photo.
  static const double _sidePanelFrom = 840;
  static const double _sidePanelWidth = 380;

  /// The bottom panel's height on a phone, and its share of a short screen at most.
  static const double _panelHeight = 268;
  static const double _panelHeightWithTool = 376;
  static const double _panelShare = 0.55;
  static const double _tabIconsFrom = 360;

  /// The brush radius on the screen, at the slider's ends.
  static const double _brushMin = 6;
  static const double _brushMax = 46;

  final _boundary = GlobalKey();
  final _tc = TransformationController();

  /// 1 = the original photo shows; 0 = it has melted away and only the cut-out is left over the backdrop.
  late final AnimationController _originalShown = AnimationController(vsync: this, value: 1);
  late CropShape _shape = widget.initial;
  int _turns = 0;
  int _size = 1024;
  double _zoom = 1;
  bool _busy = false;
  int _tab = 0;

  late final ImageBackgroundSession _session = ImageBackgroundSession(widget.bytes)..addListener(_sessionChanged);
  late final AnimationController _ring = AnimationController(vsync: this);
  ImageBackdrop _backdrop = ImageBackdrop.original;
  Color? _customColor;

  // pointer state over the frame
  int _pointers = 0;
  Offset? _downAt;
  Size _frame = Size.zero;
  bool _moved = false;
  Offset? _cursor;
  Offset _ringAt = Offset.zero;

  bool get _toolActive => _tab == 1 && _session.ready;
  bool get _brushing => _toolActive && _session.brush != ImageBackgroundBrush.pick;

  void _sessionChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _session
      ..removeListener(_sessionChanged)
      ..dispose();
    _ring.dispose();
    _originalShown.dispose();
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

  void _apply(ImageBackdrop b) {
    setState(() => _backdrop = b);
    _originalShown.animateTo(b.usesCutout ? 0 : 1, duration: AppMotion.of(context).slow, curve: AppMotion.curve);
  }

  /// The first look at the tool reads the picture and shows the result.
  Future<void> _openBackgroundTab() async {
    if (_session.started) return;
    await _session.start();
    if (!mounted) return;
    if (_session.failed) {
      showAppNotice(translate('imgbg_failed'), error: true);
    } else if (_session.ready) {
      _apply(widget.allowTransparent ? ImageBackdrop.transparent : const ImageBackdrop.color(Color(0xFFFFFFFF)));
    }
  }

  Future<void> _choose(ImageBackdrop b) async {
    if (!b.usesCutout) return _apply(b);
    if (!_session.ready) {
      await _session.start();
      if (!mounted || !_session.ready) return;
    }
    _apply(b);
  }

  /// A change on the picture while it shows the original: show the removal instead.
  void _showRemoval() {
    if (_backdrop == ImageBackdrop.original && _session.ready) {
      _apply(widget.allowTransparent ? ImageBackdrop.transparent : const ImageBackdrop.color(Color(0xFFFFFFFF)));
    }
  }

  (int, int)? _toLow(Offset local) {
    final scene = _tc.toScene(local);
    final hit = bgFramePointToSource(
      sceneX: scene.dx,
      sceneY: scene.dy,
      frameWidth: _frame.width,
      frameHeight: _frame.height,
      quarterTurns: _turns,
      sourceWidth: _session.lowWidth,
      sourceHeight: _session.lowHeight,
    );
    if (hit == null) return null;
    final x = hit.$1.floor().clamp(0, _session.lowWidth - 1);
    final y = hit.$2.floor().clamp(0, _session.lowHeight - 1);
    return (x, y);
  }

  double get _brushLowRadius {
    final perFrame = bgSourcePerFramePixel(
      frameWidth: _frame.width,
      frameHeight: _frame.height,
      quarterTurns: _turns,
      sourceWidth: _session.lowWidth,
      sourceHeight: _session.lowHeight,
    );
    return _brushScreenRadius * perFrame / _tc.value.getMaxScaleOnAxis();
  }

  double get _brushScreenRadius => _brushMin + (_brushMax - _brushMin) * _session.brushSize;

  void _pointerDown(PointerDownEvent e) {
    _pointers++;
    _downAt = e.localPosition;
    _moved = false;
    if (!_toolActive) return;
    if (_brushing && _pointers == 1 && (e.buttons & kPrimaryButton != 0 || e.kind != PointerDeviceKind.mouse)) {
      final p = _toLow(e.localPosition);
      if (p != null) {
        _showRemoval();
        _session.startStroke(p.$1.toDouble(), p.$2.toDouble(), _brushLowRadius);
      }
    }
    setState(() => _cursor = e.localPosition);
  }

  void _pointerMove(PointerMoveEvent e) {
    final d = _downAt;
    if (d != null && (e.localPosition - d).distance > kTouchSlop) _moved = true;
    if (!_toolActive) return;
    if (_brushing) {
      final p = _toLow(e.localPosition);
      if (p != null) _session.extendStroke(p.$1.toDouble(), p.$2.toDouble());
      setState(() => _cursor = e.localPosition);
    }
  }

  void _pointerUp(PointerUpEvent e) {
    final d = _downAt;
    final wasSingle = _pointers == 1;
    _pointers = _pointers > 0 ? _pointers - 1 : 0;
    if (!_toolActive) return;
    if (_brushing) {
      _session.endStroke();
      setState(() => _cursor = null);
      return;
    }
    if (wasSingle && !_moved && d != null && e.kind != PointerDeviceKind.trackpad) {
      final p = _toLow(d);
      if (p != null) {
        _showRemoval();
        _session.tapAt(p.$1, p.$2);
        setState(() => _ringAt = d);
        _ring
          ..duration = AppMotion.of(context).slow
          ..forward(from: 0);
      }
    }
  }

  void _pointerCancel(PointerCancelEvent e) {
    _pointers = _pointers > 0 ? _pointers - 1 : 0;
    _session.endStroke();
  }

  Future<void> _pickCustom() async {
    var picked = _customColor ?? context.colors.primary;
    final ok = await showAppSheet<bool>(
      context,
      (ctx) => StatefulBuilder(
        builder: (ctx, set) => AppSheetContent(
          title: translate('imgbg_custom'),
          children: [
            StudioColorField(
              value: picked,
              onChanged: (v) {
                if (v == null) return;
                set(() => picked = v);
                if (_session.ready) {
                  _customColor = v;
                  _apply(ImageBackdrop.color(v));
                }
              },
            ),
            const SizedBox(height: AppSpace.md),
            AppButton.primary(label: translate('imgbg_apply'), expand: true, onPressed: () => Navigator.pop(ctx, true)),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _customColor = picked);
    await _choose(ImageBackdrop.color(picked));
  }

  Future<void> _done(Size frame) async {
    setState(() => _busy = true);
    try {
      if (_session.ready) {
        // a fade still running must not end up in the file, nor the cut-out over a restored original
        _originalShown.value = _backdrop.usesCutout ? 0 : 1;
        if (_backdrop.usesCutout) await _session.applyFullResolution();
        if (!mounted) return;
        await WidgetsBinding.instance.endOfFrame;
        if (!mounted) return;
      }
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

  Widget _clipped(Widget child) =>
      _shape == CropShape.circle ? ClipOval(child: child) : ClipRRect(borderRadius: BorderRadius.circular(4), child: child);

  Widget _stage(Size frame) {
    final cut = _session.image;
    final showCut = cut != null && (_backdrop.usesCutout || _originalShown.isAnimating);
    _frame = frame;
    final content = SizedBox(
      width: frame.width,
      height: frame.height,
      child: Stack(fit: StackFit.expand, children: [
        ImageBackdropFill(_backdrop),
        InteractiveViewer(
          transformationController: _tc,
          minScale: 1,
          maxScale: 6,
          panEnabled: !_brushing,
          scaleEnabled: !_brushing,
          onInteractionUpdate: (_) => setState(() => _zoom = _tc.value.getMaxScaleOnAxis()),
          child: RotatedBox(
            quarterTurns: _turns,
            child: Stack(fit: StackFit.expand, children: [
              FadeTransition(
                opacity: _originalShown,
                child: Image.memory(widget.bytes, width: frame.width, height: frame.height, fit: BoxFit.cover, gaplessPlayback: true, errorBuilder: (_, _, _) => const SizedBox.expand()),
              ),
              if (showCut) RawImage(image: cut, width: frame.width, height: frame.height, fit: BoxFit.cover, filterQuality: FilterQuality.medium),
            ]),
          ),
        ),
      ]),
    );
    return Stack(alignment: Alignment.center, children: [
      if (_backdrop == ImageBackdrop.transparent)
        IgnorePointer(child: SizedBox.fromSize(size: frame, child: _clipped(const ImageCheckerboard()))),
      MouseRegion(
        cursor: !_toolActive
            ? MouseCursor.defer
            : (_brushing ? SystemMouseCursors.none : SystemMouseCursors.precise),
        onHover: _brushing ? (e) => setState(() => _cursor = e.localPosition) : null,
        onExit: (_) {
          if (_cursor != null) setState(() => _cursor = null);
        },
        child: Listener(
          key: const ValueKey('crop_frame'),
          behavior: HitTestBehavior.translucent,
          onPointerDown: _pointerDown,
          onPointerMove: _pointerMove,
          onPointerUp: _pointerUp,
          onPointerCancel: _pointerCancel,
          child: RepaintBoundary(key: _boundary, child: _clipped(content)),
        ),
      ),
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
      IgnorePointer(
        child: SizedBox.fromSize(
          size: frame,
          child: CustomPaint(painter: ImageTapRing(_ring, _ringAt, Theme.of(context).colorScheme.primary)),
        ),
      ),
      if (_brushing && _cursor != null)
        IgnorePointer(
          child: SizedBox.fromSize(
            size: frame,
            child: CustomPaint(painter: ImageBrushCursor(_cursor!, _brushScreenRadius)),
          ),
        ),
      AnimatedSwitcher(
        duration: AppMotion.of(context).base,
        child: _session.preparing
            ? ImageBackgroundWorking(
                key: const ValueKey('imgbg_working'),
                size: frame,
                circle: _shape == CropShape.circle,
              )
            : const SizedBox.shrink(),
      ),
    ]);
  }

  Widget _adjust(Size frame) {
    final c = context.colors;
    return Column(mainAxisSize: MainAxisSize.min, children: [
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
              label: Text(label, style: TextStyle(fontFamily: AppFonts.family)),
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
            label: Text('$label · $px', style: TextStyle(fontFamily: AppFonts.family)),
            selected: _size == px,
            onSelected: (_) => setState(() => _size = px),
          ),
      ]),
    ]);
  }

  Widget _backgroundTool({required bool wide}) => ImageBackgroundTool(
        session: _session,
        original: widget.bytes,
        selected: _backdrop,
        allowTransparent: widget.allowTransparent,
        wide: wide,
        customColor: _customColor,
        onPick: _choose,
        onCustom: _pickCustom,
        onToolUsed: _showRemoval,
      );

  Widget _tabs(bool icons) => AppTabs(
        key: const ValueKey('crop_tabs'),
        expand: true,
        index: _tab,
        onChanged: (i) {
          setState(() => _tab = i);
          if (i == 1) _openBackgroundTab();
        },
        items: [
          AppTabItem(translate('imgbg_tab_adjust'), icon: icons ? Icons.tune_rounded : null),
          AppTabItem(translate('imgbg_tab_background'), icon: icons ? Icons.auto_awesome_rounded : null),
        ],
      );

  Widget _useButton(Size frame) => AppButton.primary(
        key: const ValueKey('crop_use_photo'),
        label: _t('استخدام الصورة', 'Use photo'),
        icon: Icons.check_rounded,
        size: AppButtonSize.lg,
        expand: true,
        busy: _busy,
        onPressed: _busy || _session.preparing ? null : () => _done(frame),
      );

  Widget _bottomPanel(Size frame, bool tool, double height) {
    final c = context.colors;
    final showTool = tool && _tab == 1;
    final icons = MediaQuery.sizeOf(context).width >= _tabIconsFrom; // both labels fit a small phone without them
    return Container(
      height: height,
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
      ),
      child: Column(children: [
        if (tool) ...[
          _tabs(icons),
          const SizedBox(height: AppSpace.xs),
        ],
        Expanded(
          child: SingleChildScrollView(
            child: showTool ? _backgroundTool(wide: false) : _adjust(frame),
          ),
        ),
        const SizedBox(height: AppSpace.xs),
        _useButton(frame),
      ]),
    );
  }

  Widget _sidePanel(Size frame, bool tool) {
    final c = context.colors;
    return Container(
      width: _sidePanelWidth,
      padding: const EdgeInsets.all(AppSpace.lg),
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: const BorderRadiusDirectional.horizontal(start: Radius.circular(26)),
      ),
      child: Column(children: [
        if (tool) ...[
          _tabs(true),
          const SizedBox(height: AppSpace.md),
        ],
        Expanded(
          child: SingleChildScrollView(
            child: tool && _tab == 1 ? _backgroundTool(wide: true) : _adjust(frame),
          ),
        ),
        const SizedBox(height: AppSpace.md),
        _useButton(frame),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tool = widget.allowBackground && imageBackgroundAvailable();
    return Scaffold(
      backgroundColor: const Color(0xFF0B0F0E),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        // the theme's own app-bar title / icon colours are dark: on this black page the title and the icons vanished
        iconTheme: const IconThemeData(color: Colors.white),
        actionsIconTheme: const IconThemeData(color: Colors.white),
        titleTextStyle: TextStyle(fontFamily: AppFonts.family, fontSize: 20, color: Colors.white, fontWeight: FontWeight.w800),
        title: Text(_t('تعديل الصورة', 'Edit photo')),
        actions: [
          // backgrounds, signatures, documents … sometimes must stay exactly as they are
          if (widget.allowOriginal)
            TextButton(
              key: const ValueKey('crop_use_original'),
              onPressed: () => Navigator.pop(context, widget.bytes),
              child: Text(_t('استخدام الأصل', 'Use original'),
                  style: TextStyle(fontFamily: AppFonts.family, color: Colors.white, fontWeight: FontWeight.w700)),
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
          final side = box.maxWidth >= _sidePanelFrom;
          final panelH = side ? 0.0 : (tool ? _panelHeightWithTool : _panelHeight).clamp(0.0, box.maxHeight * _panelShare);
          final stageW = side ? box.maxWidth - _sidePanelWidth : box.maxWidth;
          final stageH = box.maxHeight - panelH;
          final edge = (stageW < stageH ? stageW : stageH) * 0.86;
          final frame = _shape == CropShape.wide ? Size(edge, edge * 9 / 16) : Size(edge, edge);
          final stage = Center(child: _stage(frame));
          if (side) {
            return Row(children: [Expanded(child: stage), _sidePanel(frame, tool)]);
          }
          return Column(children: [Expanded(child: stage), _bottomPanel(frame, tool, panelH)]);
        }),
      ),
    );
  }
}
