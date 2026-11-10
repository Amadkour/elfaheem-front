// lib/design/app_image_background.dart
//
// The Background tool of the app cropper (app_image_cropper.dart): remove a picture's background, then leave it
// transparent or put a colour or an organic gradient behind the subject.
//
// Everything runs on the device with no model and no server call (D-510): the pure logic is
// image_background_engine.dart, this file decodes the picture, keeps the person's steps and shows the result. The first
// look at the tool removes what the border says is background; then a tap on the picture removes that colour, a tap on
// something removed brings it back, and two brushes cover the rest. Heavy work runs on an isolate on a phone and in
// small time slices on the web (no isolates there). The result is layered over the chosen [ImageBackdrop] in the
// widget tree, so the cropper's own capture produces the final PNG, zoom, rotation and shape included; the checkerboard
// that shows transparency is drawn OUTSIDE the captured area and never reaches the file.
//
// The tool is hidden by the kill switch `image.background`; see [imageBackgroundAvailable].
library;

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';

import 'app_buttons.dart';
import 'app_contrast.dart';
import 'app_display.dart' show syncMotionLoop;
import 'app_kit.dart' show appText;
import 'app_mesh.dart';
import 'app_switch.dart';
import 'app_tokens.dart';
import 'image_background_engine.dart';
import 'studio/studio_props.dart' show studioHex;

const String kImageBackgroundFeature = 'image.background';

/// The tool is free and local: only the kill switch hides it.
bool imageBackgroundAvailable() => !AppConfig.disableList.contains(kImageBackgroundFeature);

enum ImageBackgroundBrush { pick, restore, erase }

/// Above this many pixels a phone does the first analysis on an isolate; the web has none.
const int _sliceMs = 10;

/// How far the first automatic result may go before it is tried again more carefully.
const int _guessRetries = 2;
const double _guessMinCoverage = 0.18;
const double _guessTighten = 0.55;
const double _guessPlainSpread = 2.5;

class _RenderJob {
  const _RenderJob(this.fields, this.source, this.softness);
  final BgFields fields;
  final BgRaster source;
  final double softness;
}

BgOutput _runJob(BgJob job) {
  final out = BgOutput();
  bgDrain(bgProcess(job, out));
  return out;
}

Uint8List _runRender(_RenderJob job) {
  final out = Uint8List(job.source.rgba.length);
  bgDrain(bgRender(job.fields, job.source, job.softness, out));
  return out;
}

BgWork _makeWork(BgRaster r) => BgWork(r.width, r.height, r.rgba);

/// The state of the tool for one picture. Holds the person's steps, the working copies and the result on the screen.
class ImageBackgroundSession extends ChangeNotifier {
  ImageBackgroundSession(this.bytes);

  /// A session already holding a result, for tests of the panel (nothing is decoded).
  @visibleForTesting
  ImageBackgroundSession.preview({this.coverage, List<Color> suggested = const [], bool busyBackground = false})
      : bytes = Uint8List(0),
        started = true,
        _previewOnly = true,
        suggestedColours = suggested {
    if (busyBackground) estimate = const BgEstimate([], 0, false);
  }

  final Uint8List bytes;
  bool _previewOnly = false;

  bool started = false;
  bool preparing = false;
  bool failed = false;
  BgEstimate? estimate;
  double? coverage;
  List<Color> suggestedColours = const [];
  ImageBackgroundBrush brush = ImageBackgroundBrush.pick;
  double tolerance = kBgDefaultTolerance;
  double softness = kBgDefaultSoftness;
  double brushSize = 0.3;
  bool holes = false;

  final List<BgOp> _ops = [];
  final List<BgOp> _redo = [];
  BgWork? _work;
  BgRaster? _display;
  BgFields? _fields;
  int _sourceWidth = 0, _sourceHeight = 0;

  ui.Image? _image;
  bool _dirty = false, _running = false, _disposed = false;
  Completer<void>? _settled;
  bool _stroking = false;

  /// The result to show over the backdrop.
  ui.Image? get image => _image;
  bool get ready => _work != null && _image != null;
  bool get busy => preparing;

  /// Anything still being worked out; tests wait on it.
  @visibleForTesting
  bool get working => preparing || _running || _dirty;
  bool get canUndo => _ops.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;
  bool get hasSteps => _ops.isNotEmpty || _redo.isNotEmpty;
  bool get _unlikelyBackground => estimate?.clusters.isEmpty ?? false;

  bool get busyBackground => _unlikelyBackground && !hasSteps;
  int get lowWidth => _work?.width ?? 0;
  int get lowHeight => _work?.height ?? 0;

  @override
  void dispose() {
    _disposed = true;
    _settle();
    _image?.dispose();
    _image = null;
    super.dispose();
  }

  static Future<BgRaster> _decode(Uint8List bytes, int maxSide, void Function(int, int) onSize) async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    final codec = await ui.instantiateImageCodecWithSize(buffer, getTargetSize: (w, h) {
      onSize(w, h);
      final (tw, th) = bgFitWithin(w, h, maxSide);
      return ui.TargetImageSize(width: tw, height: th);
    });
    final frame = await codec.getNextFrame();
    final data = await frame.image.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
    final raster = BgRaster(frame.image.width, frame.image.height, data!.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
    frame.image.dispose();
    codec.dispose();
    return raster;
  }

  /// Decodes, reads the border and shows the first result. Safe to call again; [ready] tells how it went.
  Future<void> start() async {
    if (started) return;
    started = true;
    preparing = true;
    failed = false;
    notifyListeners();
    try {
      final display = await _decode(bytes, kBgDisplaySide, (w, h) {
        _sourceWidth = w;
        _sourceHeight = h;
      });
      final raster = (display.width > display.height ? display.width : display.height) <= kBgLowSide ? display : await _decode(bytes, kBgLowSide, (_, _) {});
      if (_disposed) return;
      final work = kIsWeb ? BgWork(raster.width, raster.height, raster.rgba) : await compute(_makeWork, raster);
      if (_disposed) return;
      final found = kIsWeb ? bgEstimateBackground(work) : await compute(bgEstimateBackground, work);
      if (_disposed) return;
      _work = work;
      _display = display;
      estimate = found;
      holes = found.graphic;
      await _runNow();
      // an automatic guess that took nearly everything misjudged the picture: tighter, then leave it to the person.
      // Only on a varied border: on a truly plain one a small subject (a logo on a page) is simply small.
      final doubtful = found.clusters.isNotEmpty && found.clusters.first.spread > _guessPlainSpread;
      for (var i = 0; doubtful && i < _guessRetries && (coverage ?? 1) < _guessMinCoverage && estimate!.clusters.isNotEmpty; i++) {
        tolerance *= _guessTighten;
        await _runNow();
      }
      if (doubtful && (coverage ?? 1) < _guessMinCoverage && estimate!.clusters.isNotEmpty) {
        estimate = BgEstimate(const [], estimate!.confidence, false);
        tolerance = kBgDefaultTolerance;
        holes = false;
        await _runNow();
      }
    } catch (e) {
      failed = true;
      debugPrint('image background: $e');
    } finally {
      preparing = false;
      if (!_disposed) notifyListeners();
    }
  }

  

  BgParams get _params => BgParams(estimate: estimate ?? const BgEstimate([], 0, false), ops: List.of(_ops), tolerance: tolerance, softness: softness, holes: holes);

  /// One job at a time; changes that arrive meanwhile are folded into the next run.
  void _schedule() {
    if (_work == null || _previewOnly) return;
    _dirty = true;
    if (!_running) unawaited(_loop());
  }

  Future<void> _loop() async {
    _running = true;
    while (_dirty && !_disposed) {
      _dirty = false;
      try {
        await _runOnce();
      } catch (e) {
        debugPrint('image background: $e');
      }
    }
    _running = false;
    _settle();
  }

  Future<void> _runNow() async {
    _dirty = false;
    _running = true;
    try {
      await _runOnce();
    } finally {
      _running = false;
    }
    if (_dirty) unawaited(_loop());
  }

  void _settle() {
    final s = _settled;
    _settled = null;
    if (s != null && !s.isCompleted) s.complete();
  }

  Future<void> _runOnce() async {
    // first the small copy (instant feedback), then the screen's size once nothing newer is waiting
    final job = BgJob(_work!, _params, _work!);
    final out = kIsWeb ? await _sliced(job) : await compute(_runJob, job);
    if (_disposed || out == null) return;
    _fields = out.fields;
    coverage = out.fields?.coverage;
    if (suggestedColours.isEmpty) {
      suggestedColours = [for (final c in bgSuggestColours(_work!, out.fields!.removed)) Color(0xFF000000 | c)];
    }
    await _show(out.rgba!, out.width, out.height);
    final display = _display!;
    if (_dirty || (display.width == out.width && display.height == out.height)) return;
    final rgba = await _renderAt(out.fields!, display);
    if (_disposed || rgba == null) return;
    await _show(rgba, display.width, display.height);
  }

  /// [source] rendered from [fields], off the UI thread; null when a newer change arrived (web only, where it can stop).
  Future<Uint8List?> _renderAt(BgFields fields, BgRaster source) async {
    if (!kIsWeb) return compute(_runRender, _RenderJob(fields, source, softness));
    final rgba = Uint8List(source.rgba.length);
    final sw = Stopwatch()..start();
    for (final _ in bgRender(fields, source, softness, rgba)) {
      if (sw.elapsedMilliseconds >= _sliceMs) {
        await Future<void>.delayed(Duration.zero);
        if (_disposed || _dirty) return null;
        sw.reset();
      }
    }
    return rgba;
  }

  Future<BgOutput?> _sliced(BgJob job) async {
    final out = BgOutput();
    final sw = Stopwatch()..start();
    for (final _ in bgProcess(job, out)) {
      if (sw.elapsedMilliseconds >= _sliceMs) {
        await Future<void>.delayed(Duration.zero);
        if (_disposed) return null;
        sw.reset();
      }
    }
    return out;
  }

  Future<void> _show(Uint8List rgba, int width, int height) async {
    final done = Completer<ui.Image>();
    ui.decodeImageFromPixels(rgba, width, height, ui.PixelFormat.rgba8888, done.complete);
    final next = await done.future;
    if (_disposed) {
      next.dispose();
      return;
    }
    final old = _image;
    _image = next;
    notifyListeners();
    if (old != null) WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
  }

  /// The full-resolution result for the file (the cap of [kBgFullSide] is the guard for very large pictures). Does
  /// nothing if the screen copy already is the full picture.
  Future<void> applyFullResolution() async {
    await _waitSettled();
    final fields = _fields;
    if (_disposed || fields == null) return;
    final (fullW, fullH) = bgFitWithin(_sourceWidth, _sourceHeight, kBgFullSide);
    final shown = _display;
    if (shown != null && shown.width >= fullW && shown.height >= fullH) return;
    final source = await _decode(bytes, kBgFullSide, (_, _) {});
    if (_disposed) return;
    _dirty = false;
    final rgba = await _renderAt(fields, source);
    if (_disposed || rgba == null) return;
    await _show(rgba, source.width, source.height);
  }

  Future<void> _waitSettled() async {
    if (!_running) return;
    await (_settled ??= Completer<void>()).future;
  }

  void setBrush(ImageBackgroundBrush b) {
    if (brush == b) return;
    brush = b;
    notifyListeners();
  }

  void setTolerance(double v) {
    tolerance = v;
    _schedule();
    notifyListeners();
  }

  void setSoftness(double v) {
    softness = v;
    _schedule();
    notifyListeners();
  }

  void setBrushSize(double v) {
    brushSize = v;
    notifyListeners();
  }

  void setHoles(bool v) {
    holes = v;
    _schedule();
    notifyListeners();
  }

  void _add(BgOp op) {
    _ops.add(op);
    _redo.clear();
    _schedule();
    notifyListeners();
  }

  void undo() {
    if (_ops.isEmpty) return;
    _redo.add(_ops.removeLast());
    _schedule();
    notifyListeners();
  }

  void redo() {
    if (_redo.isEmpty) return;
    _ops.add(_redo.removeLast());
    _schedule();
    notifyListeners();
  }

  /// Back to what the border alone said, every step and slider undone.
  void reset() {
    _ops.clear();
    _redo.clear();
    tolerance = kBgDefaultTolerance;
    softness = kBgDefaultSoftness;
    holes = estimate?.graphic ?? false;
    _schedule();
    notifyListeners();
  }

  /// A tap on the small copy: what is kept is removed, what is removed comes back.
  void tapAt(int x, int y) {
    final fields = _fields;
    if (fields == null) return;
    final removed = fields.removed[y * fields.width + x] == 1;
    _add(removed ? BgOp.keep(x, y) : BgOp.pick(x, y));
  }

  void startStroke(double x, double y, double radius) {
    _stroking = true;
    _add(BgOp.stroke(brush == ImageBackgroundBrush.erase ? BgOpKind.erase : BgOpKind.restore, [x, y], radius));
  }

  void extendStroke(double x, double y) {
    if (!_stroking || _ops.isEmpty) return;
    _ops[_ops.length - 1] = _ops.last.extendedTo(x, y);
    _schedule();
  }

  void endStroke() => _stroking = false;
}

enum ImageBackdropKind { original, transparent, color, mesh }

/// What sits behind the subject.
@immutable
class ImageBackdrop {
  const ImageBackdrop._(this.kind, this.color, this.seed);
  const ImageBackdrop.color(Color this.color)
      : kind = ImageBackdropKind.color,
        seed = 0;

  /// [color] null is the brand colour.
  const ImageBackdrop.mesh(this.color, this.seed) : kind = ImageBackdropKind.mesh;

  static const original = ImageBackdrop._(ImageBackdropKind.original, null, 0);
  static const transparent = ImageBackdrop._(ImageBackdropKind.transparent, null, 0);

  final ImageBackdropKind kind;
  final Color? color;
  final int seed;

  bool get usesCutout => kind != ImageBackdropKind.original;

  @override
  bool operator ==(Object other) => other is ImageBackdrop && other.kind == kind && other.color == color && other.seed == seed;

  @override
  int get hashCode => Object.hash(kind, color, seed);
}

/// Paints [backdrop] (nothing for the original and for transparent).
class ImageBackdropFill extends StatelessWidget {
  const ImageBackdropFill(this.backdrop, {super.key});

  final ImageBackdrop backdrop;

  @override
  Widget build(BuildContext context) => switch (backdrop.kind) {
        ImageBackdropKind.color => ColoredBox(color: backdrop.color!),
        ImageBackdropKind.mesh => AppMeshSurface(color: backdrop.color, seed: backdrop.seed),
        _ => const SizedBox.expand(),
      };
}

/// The usual sign of transparency. Never inside the captured area.
class ImageCheckerboard extends StatelessWidget {
  const ImageCheckerboard({super.key});

  @override
  Widget build(BuildContext context) => const RepaintBoundary(child: CustomPaint(painter: _CheckerPainter(), size: Size.infinite));
}

class _CheckerPainter extends CustomPainter {
  const _CheckerPainter();

  static const double _cell = 10;
  static const Color _light = Color(0xFFFFFFFF);
  static const Color _dark = Color(0xFFDDE2E8);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = _light);
    final dark = Paint()..color = _dark;
    for (var row = 0; row * _cell < size.height; row++) {
      for (var col = row.isOdd ? 1 : 0; col * _cell < size.width; col += 2) {
        canvas.drawRect(Rect.fromLTWH(col * _cell, row * _cell, _cell, _cell), dark);
      }
    }
  }

  @override
  bool shouldRepaint(_CheckerPainter old) => false;
}

/// The moving light over the photo while the picture is read. It sits above the captured area.
class ImageBackgroundWorking extends StatefulWidget {
  const ImageBackgroundWorking({super.key, required this.size, required this.circle});

  final Size size;
  final bool circle;

  @override
  State<ImageBackgroundWorking> createState() => _ImageBackgroundWorkingState();
}

class _ImageBackgroundWorkingState extends State<ImageBackgroundWorking> with SingleTickerProviderStateMixin {
  late final AnimationController _light = AnimationController(vsync: this, duration: const Duration(milliseconds: 1700));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    syncMotionLoop(context, _light, rest: 0.5);
  }

  @override
  void dispose() {
    _light.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final painted = SizedBox.fromSize(
      size: widget.size,
      child: IgnorePointer(child: CustomPaint(painter: _LightPainter(_light, c.primaryLight))),
    );
    return SizedBox.fromSize(
      size: widget.size,
      child: Stack(alignment: Alignment.center, children: [
        widget.circle ? ClipOval(child: painted) : ClipRRect(borderRadius: BorderRadius.circular(AppRadius.chip), child: painted),
        Padding(
          padding: const EdgeInsets.all(AppSpace.xs),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: DecoratedBox(
              decoration: BoxDecoration(color: _glass, borderRadius: AppRadius.cardAll),
              child: Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.md, AppSpace.sm, AppSpace.md, AppSpace.sm),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.auto_fix_high_rounded, size: AppIconSize.sm, color: _ink),
                  const SizedBox(width: AppSpace.xs),
                  Text(translate('imgbg_working'), style: appText(13, w: FontWeight.w600, c: _ink)),
                ]),
              ),
            ),
          ),
        ),
      ]),
    );
  }

  // the cropper's stage is dark in every theme, like its app bar
  static const Color _ink = Color(0xFFFFFFFF);
  static const Color _glass = Color(0xB3101514);
}

class _LightPainter extends CustomPainter {
  _LightPainter(this.t, this.tint) : super(repaint: t);

  final Animation<double> t;
  final Color tint;

  static const Color _white = Color(0xFFFFFFFF);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..color = const Color(0x33000000));
    final band = size.longestSide * 0.7;
    final x = -band + t.value * (size.width + band * 2);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(x, 0),
          Offset(x + band, band * 0.45),
          [_white.withValues(alpha: 0), tint.withValues(alpha: 0.22), _white.withValues(alpha: 0.42), tint.withValues(alpha: 0.22), _white.withValues(alpha: 0)],
          const [0, 0.3, 0.5, 0.7, 1],
        ),
    );
  }

  @override
  bool shouldRepaint(_LightPainter old) => old.t != t || old.tint != tint;
}

/// The ring where a tap landed, drawn in the frame's coordinates.
class ImageTapRing extends CustomPainter {
  ImageTapRing(this.t, this.center, this.color) : super(repaint: t);

  final Animation<double> t;
  final Offset center;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final v = t.value;
    if (v <= 0 || v >= 1) return;
    canvas.drawCircle(
      center,
      8 + v * 26,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..color = color.withValues(alpha: 1 - v),
    );
  }

  @override
  bool shouldRepaint(ImageTapRing old) => old.center != center || old.color != color;
}

/// The brush outline over the picture.
class ImageBrushCursor extends CustomPainter {
  const ImageBrushCursor(this.center, this.radius);

  final Offset center;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawCircle(center, radius + 1, Paint()..style = PaintingStyle.stroke..strokeWidth = 3..color = const Color(0x66000000));
    canvas.drawCircle(center, radius, Paint()..style = PaintingStyle.stroke..strokeWidth = 1.5..color = const Color(0xFFFFFFFF));
  }

  @override
  bool shouldRepaint(ImageBrushCursor old) => old.center != center || old.radius != radius;
}

/// The panel of the tool. [wide] lays the choices in rows (a side panel), otherwise they are one strip that scrolls
/// sideways.
class ImageBackgroundTool extends StatelessWidget {
  const ImageBackgroundTool({
    super.key,
    required this.session,
    required this.original,
    required this.selected,
    required this.allowTransparent,
    required this.wide,
    required this.customColor,
    required this.onPick,
    required this.onCustom,
    required this.onToolUsed,
  });

  final ImageBackgroundSession session;
  final Uint8List original;
  final ImageBackdrop selected;
  final bool allowTransparent, wide;
  final Color? customColor;
  final ValueChanged<ImageBackdrop> onPick;
  final VoidCallback onCustom;

  /// A slider moved or a tool chosen: the cropper shows the removal if the person was looking at the original.
  final VoidCallback onToolUsed;

  /// Kept that much or more of the picture, there was little background to take away.
  static const double coverageHigh = 0.93;

  /// Kept that little, too much went.
  static const double coverageLow = 0.05;
  static const int _maxSuggested = 5;

  /// Gradient hues beside the brand's. Not the theme's accent: a gold darkened for the fill's ink turns olive.
  static const Color _sky = Color(0xFF2F7DE1);
  static const Color _teal = Color(0xFF0E8F8A);
  static const Color _rose = Color(0xFFD9467E);

  String get _hint {
    if (session.preparing) return translate('imgbg_hint_working');
    if (session.failed) return translate('imgbg_failed');
    switch (session.brush) {
      case ImageBackgroundBrush.restore:
        return translate('imgbg_hint_restore');
      case ImageBackgroundBrush.erase:
        return translate('imgbg_hint_erase');
      case ImageBackgroundBrush.pick:
        break;
    }
    final cov = session.coverage;
    if (session.busyBackground) return translate('imgbg_hint_busy');
    if (cov != null && cov >= coverageHigh) return translate('imgbg_hint_cover_high');
    if (cov != null && cov <= coverageLow) return translate('imgbg_hint_cover_low');
    return translate('imgbg_hint_ready');
  }

  Widget _sliderRow(BuildContext context, String key, String label, double value, ValueChanged<double> onChanged) {
    final c = context.colors;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: AppTouch.min),
      child: Row(children: [
        SizedBox(
          width: 92,
          child: Text(label, maxLines: 2, overflow: TextOverflow.ellipsis, style: appText(12, w: FontWeight.w600, c: c.textMedium)),
        ),
        Expanded(
          child: Slider(
            key: ValueKey(key),
            value: value.clamp(0.0, 1.0),
            semanticFormatterCallback: (v) => '$label ${(v * 100).round()}%',
            onChanged: session.ready
                ? (v) {
                    onChanged(v);
                    onToolUsed();
                  }
                : null,
          ),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final enabled = !session.preparing;
    bool same(Color a, Color b) => (a.toARGB32() & 0xFFFFFF) == (b.toARGB32() & 0xFFFFFF);
    const white = Color(0xFFFFFFFF);
    final colours = <(Color, String)>[(white, translate('imgbg_white')), (c.primary, translate('imgbg_brand'))];
    if (!same(c.accent, c.primary)) colours.add((c.accent, translate('imgbg_accent')));
    final suggested = <Color>[];
    for (final s in session.suggestedColours) {
      if (suggested.length == _maxSuggested) break;
      if (!suggested.any((x) => same(x, s)) && !colours.any((x) => same(x.$1, s))) suggested.add(s);
    }
    final custom = customColor;
    final customOn = selected.kind == ImageBackdropKind.color && custom != null && selected.color == custom;

    Widget colourTile(Color color, String label, String key) => _Tile(
          key: ValueKey(key),
          label: label,
          selected: selected == ImageBackdrop.color(color) && !customOn,
          enabled: enabled,
          onTap: () => onPick(ImageBackdrop.color(color)),
          child: ColoredBox(color: color),
        );

    Widget meshTile(Color? color, int seed, int index) => _Tile(
          key: ValueKey('imgbg_mesh_$index'),
          label: '${translate('imgbg_gradient')} ${index + 1}',
          selected: selected == ImageBackdrop.mesh(color, seed),
          enabled: enabled,
          onTap: () => onPick(ImageBackdrop.mesh(color, seed)),
          child: AppMeshSurface(color: color, seed: seed),
        );

    final groups = <(String, List<Widget>)>[
      (translate('imgbg_group_photo'), [
        _Tile(
          key: const ValueKey('imgbg_original'),
          label: translate('imgbg_original'),
          caption: translate('imgbg_original'),
          selected: selected == ImageBackdrop.original,
          enabled: enabled,
          onTap: () => onPick(ImageBackdrop.original),
          child: Image.memory(original, fit: BoxFit.cover, cacheWidth: 128, gaplessPlayback: true, errorBuilder: (_, _, _) => ColoredBox(color: c.divider)),
        ),
        if (allowTransparent)
          _Tile(
            key: const ValueKey('imgbg_remove'),
            label: translate('imgbg_remove_long'),
            caption: translate('imgbg_remove'),
            selected: selected == ImageBackdrop.transparent,
            enabled: enabled,
            onTap: () => onPick(ImageBackdrop.transparent),
            child: const Stack(fit: StackFit.expand, children: [
              ImageCheckerboard(),
              Icon(Icons.auto_fix_high_rounded, size: AppIconSize.md, color: Color(0xFF475569)),
            ]),
          ),
      ]),
      if (suggested.isNotEmpty)
        (translate('imgbg_group_suggested'), [
          for (final s in suggested) colourTile(s, '${translate('imgbg_suggested')} #${studioHex(s)}', 'imgbg_color_${studioHex(s)}'),
        ]),
      (translate('imgbg_group_colours'), [
        for (final (color, label) in colours) colourTile(color, label, 'imgbg_color_${studioHex(color)}'),
        _Tile(
          key: const ValueKey('imgbg_custom'),
          label: translate('imgbg_custom'),
          selected: customOn,
          enabled: enabled,
          onTap: onCustom,
          child: custom != null
              ? ColoredBox(color: custom, child: Icon(Icons.edit_rounded, size: AppIconSize.sm, color: ensureContrast(c.textDark, [custom], min: 3)))
              : DecoratedBox(
                  decoration: const BoxDecoration(
                    gradient: SweepGradient(colors: [
                      Color(0xFFEF4444),
                      Color(0xFFF59E0B),
                      Color(0xFF22C55E),
                      Color(0xFF3B82F6),
                      Color(0xFFA855F7),
                      Color(0xFFEF4444),
                    ]),
                  ),
                  child: Center(
                    child: DecoratedBox(
                      decoration: BoxDecoration(color: c.cardBg, shape: BoxShape.circle),
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpace.xxs / 2),
                        child: Icon(Icons.add_rounded, size: AppIconSize.sm, color: c.textDark),
                      ),
                    ),
                  ),
                ),
        ),
      ]),
      (translate('imgbg_group_gradients'), [
        meshTile(null, 3, 0),
        meshTile(_teal, 11, 1),
        meshTile(_sky, 5, 2),
        meshTile(_rose, 9, 3),
      ]),
    ];

    Widget title(String text) => Padding(
          padding: const EdgeInsetsDirectional.only(start: AppSpace.xxs, bottom: AppSpace.xxs),
          child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(12, w: FontWeight.w600, c: c.textMedium)),
        );

    final choices = wide
        ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
            for (final (name, tiles) in groups) ...[
              title(name),
              Wrap(children: tiles),
              const SizedBox(height: AppSpace.sm),
            ],
          ])
        : SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              for (final (name, tiles) in groups) ...[
                Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  title(name),
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: tiles),
                ]),
                const SizedBox(width: AppSpace.sm),
              ],
            ]),
          );

    final tools = <(ImageBackgroundBrush, String, IconData, String)>[
      (ImageBackgroundBrush.pick, translate('imgbg_tool_pick'), Icons.colorize_rounded, 'imgbg_tool_pick'),
      (ImageBackgroundBrush.restore, translate('imgbg_tool_restore'), Icons.brush_rounded, 'imgbg_tool_restore'),
      (ImageBackgroundBrush.erase, translate('imgbg_tool_erase'), Icons.auto_fix_normal_rounded, 'imgbg_tool_erase'),
    ];

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Expanded(
          child: AnimatedSwitcher(
            duration: AppMotion.of(context).base,
            layoutBuilder: (current, previous) => Stack(alignment: AlignmentDirectional.centerStart, children: [...previous, ?current]),
            child: Text(_hint, key: ValueKey(_hint), maxLines: 3, overflow: TextOverflow.ellipsis, style: appText(13, w: FontWeight.w400, c: c.textMedium)),
          ),
        ),
        AppIconButton(key: const ValueKey('imgbg_undo'), icon: Icons.undo_rounded, tooltip: translate('imgbg_undo'), onPressed: session.canUndo ? session.undo : null),
        AppIconButton(key: const ValueKey('imgbg_redo'), icon: Icons.redo_rounded, tooltip: translate('imgbg_redo'), onPressed: session.canRedo ? session.redo : null),
        AppIconButton(
          key: const ValueKey('imgbg_reset'),
          icon: Icons.restart_alt_rounded,
          tooltip: translate('imgbg_reset'),
          onPressed: session.hasSteps || session.tolerance != kBgDefaultTolerance || session.softness != kBgDefaultSoftness ? session.reset : null,
        ),
      ]),
      const SizedBox(height: AppSpace.xxs),
      _ToolPicker(
        items: tools,
        selected: session.brush,
        enabled: enabled,
        onChanged: (b) {
          session.setBrush(b);
          onToolUsed();
        },
      ),
      if (!wide) ...[
        const SizedBox(height: AppSpace.sm),
        choices,
      ],
      const SizedBox(height: AppSpace.xxs),
      _sliderRow(context, 'imgbg_tolerance', translate('imgbg_tolerance'), session.tolerance, session.setTolerance),
      _sliderRow(context, 'imgbg_softness', translate('imgbg_softness'), session.softness, session.setSoftness),
      if (session.brush != ImageBackgroundBrush.pick) _sliderRow(context, 'imgbg_brush_size', translate('imgbg_brush_size'), session.brushSize, session.setBrushSize),
      AppSwitchTile(
        key: const ValueKey('imgbg_holes'),
        title: translate('imgbg_holes'),
        value: session.holes,
        dense: true,
        padding: EdgeInsets.zero,
        onChanged: session.ready
            ? (v) {
                session.setHoles(v);
                onToolUsed();
              }
            : null,
      ),
      if (wide) ...[
        const SizedBox(height: AppSpace.sm),
        choices,
      ],
    ]);
  }
}

class _ToolPicker extends StatelessWidget {
  const _ToolPicker({required this.items, required this.selected, required this.enabled, required this.onChanged});

  final List<(ImageBackgroundBrush, String, IconData, String)> items;
  final ImageBackgroundBrush selected;
  final bool enabled;
  final ValueChanged<ImageBackgroundBrush> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ring = ensureContrast(c.primary, [c.cardBg]);
    return Row(children: [
      for (final (i, (brush, label, icon, key)) in items.indexed) ...[
        if (i > 0) const SizedBox(width: AppSpace.xxs),
        Expanded(
          child: Semantics(
            button: true,
            selected: brush == selected,
            enabled: enabled,
            label: label,
            excludeSemantics: true,
            child: InkWell(
              key: ValueKey(key),
              onTap: enabled ? () => onChanged(brush) : null,
              borderRadius: AppRadius.chipAll,
              child: AnimatedContainer(
                duration: AppMotion.of(context).fast,
                constraints: const BoxConstraints(minHeight: AppTouch.min),
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: AppSpace.xxs, vertical: AppSpace.xxs),
                decoration: BoxDecoration(
                  color: brush == selected ? c.primaryTint : null,
                  borderRadius: AppRadius.chipAll,
                  border: Border.all(color: brush == selected ? ring : c.divider, width: brush == selected ? AppBorder.focus : AppBorder.hairline),
                ),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(icon, size: AppIconSize.sm, color: brush == selected ? ring : c.textMedium),
                    const SizedBox(width: AppSpace.xxs),
                    Text(label, maxLines: 1, style: appText(12, w: FontWeight.w600, c: brush == selected ? c.textDark : c.textMedium)),
                  ]),
                ),
              ),
            ),
          ),
        ),
      ],
    ]);
  }
}

class _Tile extends StatelessWidget {
  const _Tile({super.key, required this.label, required this.selected, required this.enabled, required this.onTap, required this.child, this.caption});

  final String label;
  final String? caption;
  final bool selected, enabled;
  final VoidCallback onTap;
  final Widget child;

  static const double _visual = 52;
  static const double _captioned = 84;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final motion = AppMotion.of(context);
    final ring = ensureContrast(c.primary, [c.cardBg]);
    return Semantics(
      button: true,
      enabled: enabled,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: Tooltip(
        message: label,
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: AppRadius.chipAll,
          child: AnimatedOpacity(
            duration: motion.fast,
            opacity: enabled ? 1 : 0.5,
            child: Padding(
              padding: const EdgeInsets.all(AppSpace.xxs),
              child: SizedBox(
                width: caption == null ? _visual : _captioned,
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  AnimatedContainer(
                    duration: motion.fast,
                    curve: AppMotion.curve,
                    width: _visual,
                    height: _visual,
                    padding: const EdgeInsets.all(AppBorder.focus + 1),
                    decoration: BoxDecoration(
                      borderRadius: AppRadius.chipAll,
                      border: Border.all(color: selected ? ring : Colors.transparent, width: AppBorder.focus),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(AppRadius.chip - 3),
                      child: DecoratedBox(
                        position: DecorationPosition.foreground,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(AppRadius.chip - 3),
                          border: Border.all(color: c.divider),
                        ),
                        child: SizedBox.expand(child: child),
                      ),
                    ),
                  ),
                  if (caption != null) ...[
                    const SizedBox(height: AppSpace.xxs),
                    Text(
                      caption!,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: appText(12, w: selected ? FontWeight.w600 : FontWeight.w500, c: selected ? c.textDark : c.textMedium),
                    ),
                  ],
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
