// features/teacher/certificates/designer/cert_canvas_item.dart
//
// How one certificate element looks on the studio canvas — drawn the way the server renderer
// (certificate_design_renderer.py) draws it, so the canvas matches the issued PNG:
//   text       the cert font of the field (kCertFonts, the server's own files), Arabic → `text_ar`, one-line fields
//              shrink to the box, wrapped fields stop at max_lines
//   logo /     the image fitted (contain) and centred in the w × h box; a signature's caption lines sit centred
//   signature  ~2 units under the DRAWN image: the name at size × 0.75 slightly bold, the title at size × 0.6 with
//              opacity × 0.8, each one line shrunk to the box width
//   qr         a placeholder QR (finder squares + modules) in the field's ink on a white quiet zone
//   photo      the grey silhouette the server preview draws, circle or rounded square with a white ring
//   line       a bar of the field's colour
// Plain values only (no provider): the studio's itemBuilder and the layout tests build it directly.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';

import 'cert_studio_adapter.dart';
import 'certificate_design_models.dart';

/// The renderer's caption scales (SIG_NAME_SCALE, SIG_TITLE_SCALE) and its gap under the image (logical units).
const double kCertSigNameScale = 0.75;
const double kCertSigTitleScale = 0.6;
const double kCertSigCaptionGap = 2;

class CertFieldView extends StatelessWidget {
  const CertFieldView({
    super.key,
    required this.field,
    required this.size,
    required this.scale,
    required this.arabic,
    this.imageUrl,
    this.samples = const {},
  });

  final CertField field;

  /// The element's box in page units (the live rect while it is being resized).
  final Size size;

  /// Screen pixels per page unit.
  final double scale;

  /// Which language's text to show.
  final bool arabic;

  /// The resolved image of a logo / signature (its own `src`, else the language's default).
  final String? imageUrl;

  /// Sample values of custom placeholders.
  final Map<String, String> samples;

  @override
  Widget build(BuildContext context) {
    final f = field;
    switch (f.kind) {
      case CertFieldKind.text:
        return _text();
      case CertFieldKind.logo:
        return _CertImage(url: imageUrl, field: f, scale: scale, icon: Icons.image_outlined, label: 'certd_add_logo'.tr);
      case CertFieldKind.signature:
        return CertSignatureView(field: f, url: imageUrl, scale: scale, size: size, samples: samples, arabic: arabic);
      case CertFieldKind.line:
        return ColoredBox(color: hexToColor(f.color).withValues(alpha: f.opacity.clamp(0.0, 1.0)));
      case CertFieldKind.photo:
        return CustomPaint(painter: CertPhotoPainter(rounded: f.shape == 'rounded', opacity: f.opacity));
      case CertFieldKind.qr:
        return CustomPaint(
          painter: CertQrPainter(ink: hexToColor(f.color), opacity: f.opacity, seed: f.id.hashCode),
        );
    }
  }

  Widget _text() {
    final f = field;
    final resolved = resolveSample(certFieldRawText(f, arabic: arabic), arabic: arabic, custom: samples);
    final dir = certArabicChars.hasMatch(resolved) ? TextDirection.rtl : TextDirection.ltr;
    // the renderer drops letter spacing on Arabic text (tracking would break the joins)
    final style = dir == TextDirection.rtl
        ? certTextStyle(f, scale: scale).copyWith(letterSpacing: 0)
        : certTextStyle(f, scale: scale);
    final align = f.align == 'left' ? TextAlign.left : (f.align == 'right' ? TextAlign.right : TextAlign.center);
    final alignment =
        f.align == 'left' ? Alignment.topLeft : (f.align == 'right' ? Alignment.topRight : Alignment.topCenter);
    final text = resolved.isEmpty ? ' ' : resolved;
    final w = math.max(1.0, size.width * scale);
    final Widget body = f.maxLines <= 1
        ? FittedBox(
            fit: f.shrink ? BoxFit.scaleDown : BoxFit.none,
            alignment: alignment,
            child: Text(text, style: style, textDirection: dir, softWrap: false),
          )
        : Text(text, style: style, textAlign: align, textDirection: dir, maxLines: f.maxLines, overflow: TextOverflow.fade);
    return OverflowBox(
      alignment: Alignment.topCenter,
      minHeight: 0,
      maxHeight: double.infinity,
      minWidth: w,
      maxWidth: w,
      child: SizedBox(width: w, child: body),
    );
  }
}

/// A logo / signature image: contain + centred, or a calm placeholder when the box has no image.
class _CertImage extends StatelessWidget {
  const _CertImage({required this.url, required this.field, required this.scale, required this.icon, required this.label});

  final String? url;
  final CertField field;
  final double scale;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final u = url;
    final placeholder = CertImagePlaceholder(icon: icon, label: label, scale: scale);
    if (u == null || u.isEmpty) return placeholder;
    return Opacity(
      opacity: field.opacity.clamp(0.0, 1.0),
      child: Image.network(
        u,
        fit: BoxFit.contain,
        alignment: Alignment.center,
        errorBuilder: (_, _, _) => placeholder,
      ),
    );
  }
}

/// The dashed "no image yet" box of a logo / signature element.
class CertImagePlaceholder extends StatelessWidget {
  const CertImagePlaceholder({super.key, required this.icon, required this.label, this.scale = 1});

  final IconData icon;
  final String label;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // On the white / dark paper, not on the app surface: a neutral that reads on both.
    const ink = Color(0xFF6B7280);
    return CustomPaint(
      painter: _DashedRectPainter(color: ink.withValues(alpha: 0.7)),
      child: ColoredBox(
        color: ink.withValues(alpha: 0.08),
        child: LayoutBuilder(builder: (context, box) {
          final small = box.maxHeight < 36 || box.maxWidth < 60;
          return Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: small
                    ? Icon(icon, size: 18, color: ink)
                    : Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(icon, size: 18, color: ink),
                        const SizedBox(width: 6),
                        Text(label,
                            style: c.caption.copyWith(color: ink, fontSize: 12, fontWeight: FontWeight.w500)),
                      ]),
              ),
            ),
          );
        }),
      ),
    );
  }
}

class _DashedRectPainter extends CustomPainter {
  const _DashedRectPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final path = Path()..addRect(Offset.zero & size);
    for (final m in path.computeMetrics()) {
      var d = 0.0;
      while (d < m.length) {
        canvas.drawPath(m.extractPath(d, math.min(d + 5, m.length)), p);
        d += 9;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedRectPainter old) => old.color != color;
}

/// Where the renderer draws an image of [imageSize] pixels in a w × h box ([box], page units): contain + centred.
/// Returns the drawn rect in page units relative to the box.
Rect certContainRect(Size box, Size? imageSize) {
  if (imageSize == null || imageSize.width <= 0 || imageSize.height <= 0) return Offset.zero & box;
  final bh = box.height <= 0 ? box.width * imageSize.height / imageSize.width : box.height;
  final s = math.min(box.width / imageSize.width, bh / imageSize.height);
  final w = imageSize.width * s, h = imageSize.height * s;
  return Rect.fromLTWH((box.width - w) / 2, (bh - h) / 2, w, h);
}

/// A signature element: its image (contain, centred) and the two caption lines under the drawn image, exactly
/// where the server puts them (needs the image's size, read once it loads).
class CertSignatureView extends StatefulWidget {
  const CertSignatureView({
    super.key,
    required this.field,
    required this.url,
    required this.scale,
    required this.size,
    this.samples = const {},
    this.arabic = true,
  });

  final CertField field;
  final String? url;
  final double scale;
  final Size size;
  final Map<String, String> samples;
  final bool arabic;

  @override
  State<CertSignatureView> createState() => _CertSignatureViewState();
}

class _CertSignatureViewState extends State<CertSignatureView> {
  ImageStream? _stream;
  ImageStreamListener? _listener;
  Size? _imageSize;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolve();
  }

  @override
  void didUpdateWidget(covariant CertSignatureView old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url) {
      _imageSize = null;
      _resolve();
    }
  }

  void _resolve() {
    final u = widget.url;
    _unlisten();
    if (u == null || u.isEmpty) return;
    final stream = NetworkImage(u).resolve(createLocalImageConfiguration(context));
    final l = ImageStreamListener(
      (info, _) {
        final s = Size(info.image.width.toDouble(), info.image.height.toDouble());
        if (mounted && s != _imageSize) setState(() => _imageSize = s);
      },
      onError: (_, _) {},
    );
    stream.addListener(l);
    _stream = stream;
    _listener = l;
  }

  void _unlisten() {
    final s = _stream, l = _listener;
    if (s != null && l != null) s.removeListener(l);
    _stream = null;
    _listener = null;
  }

  @override
  void dispose() {
    _unlisten();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.field;
    final s = widget.scale;
    final hasImage = (widget.url ?? '').isNotEmpty;
    final drawn = hasImage ? certContainRect(widget.size, _imageSize) : Offset.zero & widget.size;
    final lines = <(String, double, double, double)>[
      // text, size scale, stroke (fraction of the font size), opacity factor — the renderer's numbers
      if ((f.sigName ?? '').trim().isNotEmpty) (f.sigName!, kCertSigNameScale, 0.025, 1.0),
      if ((f.sigTitle ?? '').trim().isNotEmpty) (f.sigTitle!, kCertSigTitleScale, 0.0, 0.8),
    ];
    final captions = <Widget>[];
    var y = drawn.bottom + kCertSigCaptionGap;
    for (final (raw, k, stroke, fade) in lines) {
      final text = resolveSample(raw, arabic: widget.arabic, custom: widget.samples);
      final size = math.max(6.0, f.size * k);
      final style = certTextStyle(f, scale: s, size: size, opacityFactor: fade).copyWith(height: 1.0, letterSpacing: 0);
      final arabicText = certArabicChars.hasMatch(text);
      final tp = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: arabicText ? TextDirection.rtl : TextDirection.ltr,
        maxLines: 1,
      )..layout();
      final lineH = tp.height / math.max(s, 1e-6) * (arabicText ? 1.18 : 1.12);
      tp.dispose();
      // PIL: stroke_width = max(1, round(size_px × 0.025)) pixels at RENDER_SCALE 1.6, on each side of the glyph
      final strokePx = stroke > 0 ? math.max(1 / 1.6, (size * 1.6 * stroke).roundToDouble() / 1.6) * s : 0.0;
      Widget line = Text(text,
          maxLines: 1,
          softWrap: false,
          textDirection: arabicText ? TextDirection.rtl : TextDirection.ltr,
          style: style);
      if (strokePx > 0) {
        line = Stack(children: [
          Text(text,
              maxLines: 1,
              softWrap: false,
              textDirection: arabicText ? TextDirection.rtl : TextDirection.ltr,
              style: TextStyle(
                fontFamily: style.fontFamily,
                fontFamilyFallback: style.fontFamilyFallback,
                fontSize: style.fontSize,
                height: style.height,
                foreground: Paint()
                  ..style = PaintingStyle.stroke
                  ..strokeWidth = strokePx * 2
                  ..strokeJoin = StrokeJoin.round
                  ..color = style.color ?? const Color(0xFF000000),
              )),
          line,
        ]);
      }
      captions.add(Positioned(
        left: 0,
        right: 0,
        top: y * s,
        height: lineH * s,
        child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.topCenter, child: line),
      ));
      y += lineH + 1;
    }
    return Stack(clipBehavior: Clip.none, children: [
      Positioned.fill(
        child: _CertImage(
          url: widget.url,
          field: f,
          scale: s,
          icon: Icons.draw_rounded,
          label: 'certd_add_signature'.tr,
        ),
      ),
      ...captions,
    ]);
  }
}

/// The server preview's silhouette for the student photo.
class CertPhotoPainter extends CustomPainter {
  const CertPhotoPainter({this.rounded = false, this.opacity = 1});
  final bool rounded;
  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    final side = math.min(size.width, size.height);
    final rect = Offset.zero & Size(side, side);
    final a = opacity.clamp(0.0, 1.0);
    final pad = math.max(2.0, side / 40);
    final ring = Paint()..color = const Color(0xFFFFFFFF).withValues(alpha: 0.9 * a);
    final outer = rect.inflate(pad);
    if (rounded) {
      canvas.drawRRect(RRect.fromRectAndRadius(outer, Radius.circular(side * 0.18)), ring);
    } else {
      canvas.drawOval(outer, ring);
    }
    canvas.save();
    final clip = Path();
    if (rounded) {
      clip.addRRect(RRect.fromRectAndRadius(rect, Radius.circular(side * 0.16)));
    } else {
      clip.addOval(rect);
    }
    canvas.clipPath(clip);
    canvas.drawRect(rect, Paint()..color = const Color(0xFFD6DCE2).withValues(alpha: a));
    final body = Paint()..color = const Color(0xFFAAB2BC).withValues(alpha: a);
    canvas.drawOval(Rect.fromLTRB(side * .32, side * .18, side * .68, side * .54), body);
    canvas.drawOval(Rect.fromLTRB(side * .16, side * .58, side * .84, side * 1.2), body);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CertPhotoPainter old) => old.rounded != rounded || old.opacity != opacity;
}

/// A stand-in QR code: the real one (each certificate's verification link) is drawn by the server when issuing.
/// 25 modules + a 2-module white quiet zone, like the renderer's square of side w.
class CertQrPainter extends CustomPainter {
  const CertQrPainter({required this.ink, this.opacity = 1, this.seed = 7});
  final Color ink;
  final double opacity;
  final int seed;

  static const int modules = 25, quiet = 2;

  bool _inFinder(int r, int c) {
    bool box(int r0, int c0) => r >= r0 - 1 && r <= r0 + 7 && c >= c0 - 1 && c <= c0 + 7;
    return box(0, 0) || box(0, modules - 7) || box(modules - 7, 0);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final side = math.min(size.width, size.height);
    final n = modules + 2 * quiet;
    final m = side / n;
    final a = opacity.clamp(0.0, 1.0);
    canvas.drawRect(Offset.zero & Size(side, side), Paint()..color = const Color(0xFFFFFFFF).withValues(alpha: a));
    final p = Paint()..color = ink.withValues(alpha: a);
    void cell(int r, int c) => canvas.drawRect(Rect.fromLTWH((c + quiet) * m, (r + quiet) * m, m + .3, m + .3), p);
    void finder(int r0, int c0) {
      for (var r = 0; r < 7; r++) {
        for (var c = 0; c < 7; c++) {
          final ring = r == 0 || r == 6 || c == 0 || c == 6;
          final core = r >= 2 && r <= 4 && c >= 2 && c <= 4;
          if (ring || core) cell(r0 + r, c0 + c);
        }
      }
    }

    finder(0, 0);
    finder(0, modules - 7);
    finder(modules - 7, 0);
    var x = (seed & 0x7fffffff) | 1;
    for (var r = 0; r < modules; r++) {
      for (var c = 0; c < modules; c++) {
        if (_inFinder(r, c)) continue;
        if (r == 6 || c == 6) {
          if ((r + c).isEven) cell(r, c); // timing patterns
          continue;
        }
        x = (x * 1103515245 + 12345) & 0x7fffffff;
        if ((x >> 16) & 1 == 1) cell(r, c);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CertQrPainter old) => old.ink != ink || old.opacity != opacity || old.seed != seed;
}
