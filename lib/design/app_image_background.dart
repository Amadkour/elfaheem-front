// lib/design/app_image_background.dart
//
// The Background tool of the app cropper (app_image_cropper.dart): remove a photo's background or put a colour or an
// organic gradient behind the subject.
//
// One server call per image gives a cut-out (PNG with alpha) that stays in memory. Everything after it is local: the
// cut-out is layered over the chosen [ImageBackdrop] in the widget tree, so the cropper's own capture produces the
// final PNG, zoom, rotation and shape included. The checkerboard that shows transparency is drawn OUTSIDE the
// captured area and never reaches the file.
//
// The tool is hidden for guests, for "view as" (the server refuses writes there) and by the kill switch
// `image.background`; see [imageBackgroundAvailable].
library;

import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dio/dio.dart' show CancelToken;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/features/shared/guest/guest_state.dart';
import 'package:flutter_education_app/utils/widget/view_as_state.dart';

import 'app_buttons.dart';
import 'app_contrast.dart';
import 'app_display.dart' show syncMotionLoop;
import 'app_kit.dart' show appText;
import 'app_mesh.dart';
import 'app_tokens.dart';
import 'studio/studio_props.dart' show studioHex, studioParseHex;

const String kImageBackgroundFeature = 'image.background';

/// A signed-in person who may write, with the tool switched on.
bool imageBackgroundAvailable() =>
    !AppConfig.disableList.contains(kImageBackgroundFeature) &&
    !GuestState.active &&
    !ViewAsState.active &&
    ApiClient().hasSession;

/// The server's answer, kept for as long as the cropper is open.
@immutable
class ImageCutout {
  const ImageCutout({required this.png, required this.width, required this.height, required this.coverage, required this.suggested});

  final Uint8List png;
  final int width, height;

  /// The share of the picture kept as the subject, 0 … 1.
  final double coverage;
  final List<Color> suggested;
}

/// Above this a base64 body is decoded on a background isolate (the web has none).
const int _inlineBase64Limit = 300000;

/// The largest side sent when a picture has to be re-encoded first.
const int _transcodeMaxSide = 2048;

String? _imageExtension(Uint8List b) {
  if (b.length > 3 && b[0] == 0xFF && b[1] == 0xD8) return 'jpg';
  if (b.length > 8 && b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47) return 'png';
  if (b.length > 12 && b[0] == 0x52 && b[1] == 0x49 && b[8] == 0x57 && b[9] == 0x45 && b[10] == 0x42 && b[11] == 0x50) return 'webp';
  return null;
}

/// HEIC and the like: what this device can show, as a PNG the server can read.
Future<Uint8List> _transcodeToPng(Uint8List bytes) async {
  final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
  final codec = await ui.instantiateImageCodecWithSize(buffer, getTargetSize: (w, h) {
    final longest = w > h ? w : h;
    if (longest <= _transcodeMaxSide) return ui.TargetImageSize(width: w, height: h);
    final s = _transcodeMaxSide / longest;
    return ui.TargetImageSize(width: (w * s).round(), height: (h * s).round());
  });
  final frame = await codec.getNextFrame();
  final data = await frame.image.toByteData(format: ui.ImageByteFormat.png);
  frame.image.dispose();
  codec.dispose();
  if (data == null) throw ApiException(statusCode: 0, message: translate('imgbg_failed'));
  return data.buffer.asUint8List();
}

Future<Uint8List> _decodeBase64(String s) async => kIsWeb || s.length < _inlineBase64Limit ? base64Decode(s) : compute(base64Decode, s);

/// `POST /api/v1/me/images/remove-background`. Throws only [ApiException].
Future<ImageCutout> removeImageBackground(Uint8List bytes, {CancelToken? cancelToken}) async {
  final ext = _imageExtension(bytes);
  final upload = ext == null ? await _transcodeToPng(bytes) : bytes;
  final r = await ApiClient().postMultipart(
    '/api/v1/me/images/remove-background',
    fields: const {},
    fileField: 'file',
    fileName: 'image.${ext ?? 'png'}',
    fileBytes: upload,
    cancelToken: cancelToken,
  );
  final b64 = r is Map ? r['image_b64'] : null;
  if (b64 is! String || b64.isEmpty) throw ApiException(statusCode: 0, message: translate('imgbg_failed'));
  final Uint8List png;
  try {
    png = await _decodeBase64(b64);
  } on FormatException {
    throw ApiException(statusCode: 0, message: translate('imgbg_failed'));
  }
  final raw = r['suggested_colors'];
  return ImageCutout(
    png: png,
    width: (r['width'] as num?)?.toInt() ?? 0,
    height: (r['height'] as num?)?.toInt() ?? 0,
    coverage: (r['coverage'] as num?)?.toDouble() ?? 0.5,
    suggested: [
      if (raw is List)
        for (final h in raw)
          if (studioParseHex('$h') case final Color color) color,
    ],
  );
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

/// The moving light over the photo while the server works, with a way out. It sits above the captured area.
class ImageBackgroundWorking extends StatefulWidget {
  const ImageBackgroundWorking({super.key, required this.size, required this.circle, required this.onCancel});

  final Size size;
  final bool circle;
  final VoidCallback onCancel;

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
                padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.md, AppSpace.xxs, AppSpace.xxs, AppSpace.xxs),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.auto_awesome_rounded, size: AppIconSize.sm, color: _ink),
                  const SizedBox(width: AppSpace.xs),
                  Text(translate('imgbg_working'), style: appText(13, w: FontWeight.w600, c: _ink)),
                  const SizedBox(width: AppSpace.xs),
                  TextButton(
                    key: const ValueKey('imgbg_cancel'),
                    onPressed: widget.onCancel,
                    style: TextButton.styleFrom(foregroundColor: _ink, minimumSize: const Size(AppTouch.min, AppTouch.min)),
                    child: Text(translate('imgbg_cancel'), style: appText(13, w: FontWeight.w700, c: _ink)),
                  ),
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

/// Plain values in, choices out: the panel of the tool. [wide] lays the choices in rows (a side panel), otherwise
/// they are one strip that scrolls sideways.
class ImageBackgroundTool extends StatelessWidget {
  const ImageBackgroundTool({
    super.key,
    required this.original,
    required this.selected,
    required this.working,
    required this.cutout,
    required this.allowTransparent,
    required this.wide,
    required this.customColor,
    required this.onPick,
    required this.onUndo,
    required this.onCustom,
  });

  final Uint8List original;
  final ImageBackdrop selected;
  final bool working;
  final ImageCutout? cutout;
  final bool allowTransparent, wide;
  final Color? customColor;
  final ValueChanged<ImageBackdrop> onPick;
  final VoidCallback onUndo, onCustom;

  /// Kept that much or more of the picture, there was little background to take away.
  static const double coverageHigh = 0.93;

  /// Kept that little, the subject found may not be the one meant.
  static const double coverageLow = 0.05;
  static const int _maxSuggested = 5;

  /// Gradient hues beside the brand's. Not the theme's accent: a gold darkened for the fill's ink turns olive.
  static const Color _sky = Color(0xFF2F7DE1);
  static const Color _teal = Color(0xFF0E8F8A);
  static const Color _rose = Color(0xFFD9467E);

  String get _hint {
    final cut = cutout;
    if (working) return translate('imgbg_hint_working');
    if (cut == null) return translate('imgbg_hint_start');
    if (cut.coverage >= coverageHigh) return translate('imgbg_hint_cover_high');
    if (cut.coverage <= coverageLow) return translate('imgbg_hint_cover_low');
    return translate('imgbg_hint_ready');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    bool same(Color a, Color b) => (a.toARGB32() & 0xFFFFFF) == (b.toARGB32() & 0xFFFFFF);
    const white = Color(0xFFFFFFFF);
    final colours = <(Color, String)>[(white, translate('imgbg_white')), (c.primary, translate('imgbg_brand'))];
    if (!same(c.accent, c.primary)) colours.add((c.accent, translate('imgbg_accent')));
    final suggested = <Color>[];
    for (final s in cutout?.suggested ?? const <Color>[]) {
      if (suggested.length == _maxSuggested) break;
      if (!suggested.any((x) => same(x, s)) && !colours.any((x) => same(x.$1, s))) suggested.add(s);
    }
    final custom = customColor;
    final customOn = selected.kind == ImageBackdropKind.color && custom != null && selected.color == custom;

    Widget colourTile(Color color, String label, String key) => _Tile(
          key: ValueKey(key),
          label: label,
          selected: selected == ImageBackdrop.color(color) && !customOn,
          enabled: !working,
          onTap: () => onPick(ImageBackdrop.color(color)),
          child: ColoredBox(color: color),
        );

    Widget meshTile(Color? color, int seed, int index) => _Tile(
          key: ValueKey('imgbg_mesh_$index'),
          label: '${translate('imgbg_gradient')} ${index + 1}',
          selected: selected == ImageBackdrop.mesh(color, seed),
          enabled: !working,
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
          enabled: !working,
          onTap: () => onPick(ImageBackdrop.original),
          child: Image.memory(original, fit: BoxFit.cover, cacheWidth: 128, gaplessPlayback: true),
        ),
        if (allowTransparent)
          _Tile(
            key: const ValueKey('imgbg_remove'),
            label: translate('imgbg_remove_long'),
            caption: translate('imgbg_remove'),
            selected: selected == ImageBackdrop.transparent,
            enabled: !working,
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
          enabled: !working,
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

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Row(children: [
        Expanded(
          child: AnimatedSwitcher(
            duration: AppMotion.of(context).base,
            layoutBuilder: (current, previous) => Stack(alignment: AlignmentDirectional.centerStart, children: [...previous, ?current]),
            child: Text(_hint, key: ValueKey(_hint), style: appText(13, w: FontWeight.w400, c: c.textMedium)),
          ),
        ),
        if (selected != ImageBackdrop.original && !working)
          AppButton.ghost(
            key: const ValueKey('imgbg_undo'),
            label: translate('imgbg_undo'),
            icon: Icons.undo_rounded,
            onPressed: onUndo,
          ),
      ]),
      const SizedBox(height: AppSpace.xs),
      choices,
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
  static const double _captioned = 68;

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
